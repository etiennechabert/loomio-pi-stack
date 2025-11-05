# Loomio Pi Stack - Production RAM Mode (Raspberry Pi)
SHELL := /bin/bash

.PHONY: help start stop restart down status logs backup restore sync-gdrive update-images migrate create-admin health restart-unhealthy rails-console db-console init-env init-gdrive clean

# Default target
.DEFAULT_GOAL := help

# Colors
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

##@ General

help: ## Display this help message
	@echo "$(BLUE)Loomio Pi Stack - Makefile Commands$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(YELLOW)<target>$(NC)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Container Management

start: ## Start all containers (auto-restores last backup if DB empty)
	@echo "$(BLUE)Starting containers...$(NC)"
	docker compose up -d
	@echo "$(GREEN)✓ Containers started$(NC)"
	@echo "Access Loomio at: http://localhost:3000"

stop: ## Stop all containers
	@echo "$(YELLOW)Stopping containers...$(NC)"
	docker compose stop
	@echo "$(GREEN)✓ Containers stopped$(NC)"

restart: ## Restart all containers
	@echo "$(YELLOW)Restarting containers...$(NC)"
	docker compose restart
	@echo "$(GREEN)✓ Containers restarted$(NC)"

down: ## Stop and remove all containers
	@echo "$(RED)Stopping and removing containers...$(NC)"
	docker compose down
	@echo "$(GREEN)✓ Containers removed$(NC)"

status: ## Show container status
	@docker compose ps

logs: ## Show container logs (usage: make logs [SERVICE=app])
	@docker compose logs -f $(if $(SERVICE),$(SERVICE),)

##@ Manual Operations

update-images: ## Pull latest Docker images (manual)
	@echo "$(BLUE)Pulling latest images...$(NC)"
	docker compose pull
	@echo "$(GREEN)✓ Images updated$(NC)"
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. make stop"
	@echo "  2. make start"
	@echo "  3. make migrate  (if needed)"
	@echo "  4. make backup"

migrate: ## Run database migrations (manual)
	@echo "$(BLUE)Running migrations...$(NC)"
	docker exec loomio-app bundle exec rake db:migrate

backup: ## Create manual database backup
	@./scripts/backup-db.sh

restore: ## Restore from production/backups/ (interactive)
	@./scripts/restore-db-manual.sh

sync-gdrive: ## Upload backups to Google Drive
	@./scripts/sync-to-gdrive.sh

##@ Admin Management

create-admin: ## Create admin user (prints password directly)
	@echo "$(BLUE)Creating admin user...$(NC)"
	@read -p "Enter email: " email; 	read -p "Enter name: " name; 	docker exec loomio-app bundle exec rails runner scripts/ruby/create_admin.rb "$$email" "$$name"

##@ Health & Monitoring

health: ## Check container health
	@./scripts/health-check.sh

restart-unhealthy: ## Restart unhealthy containers (automatic)
	@./scripts/restart-unhealthy.sh

##@ Console Access

rails-console: ## Open Rails console
	@docker exec -it loomio-app bundle exec rails console

db-console: ## Open PostgreSQL console
	@docker exec -it loomio-db psql -U $(shell grep POSTGRES_USER .env | cut -d '=' -f2) -d $(shell grep POSTGRES_DB .env | cut -d '=' -f2)

##@ Setup (One-Time)

install: ## Install Docker and dependencies (Raspberry Pi)
	@echo "$(BLUE)Installing Docker and dependencies...$(NC)"
	@if command -v docker >/dev/null 2>&1; then 		echo "$(GREEN)✓ Docker already installed$(NC)"; 	else 		echo "Installing Docker..."; 		curl -fsSL https://get.docker.com -o get-docker.sh; 		sudo sh get-docker.sh; 		rm get-docker.sh; 		sudo usermod -aG docker $$USER; 		echo "$(YELLOW)⚠ Please log out and back in for Docker permissions$(NC)"; 	fi
	@echo "Installing dependencies..."
	@sudo apt update
	@sudo apt install -y git openssl make rclone
	@echo "$(GREEN)✓ Installation complete!$(NC)"

init-env: ## Setup production environment (.env file)
	@echo "$(BLUE)Initializing production environment...$(NC)"
	@if [ -f .env ]; then 		echo "$(RED)✗ .env file already exists!$(NC)"; 		echo "Rename it first: mv .env .env.backup"; 		exit 1; 	fi
	@cp .env.production .env
	@echo "$(BLUE)Generating production secrets...$(NC)"
	@SECRET_KEY_BASE=$$(openssl rand -hex 64); 	LOOMIO_HMAC_KEY=$$(openssl rand -hex 32); 	DEVISE_SECRET=$$(openssl rand -hex 32); 	BACKUP_ENCRYPTION_KEY=$$(openssl rand -hex 32); 	POSTGRES_PASSWORD=$$(openssl rand -base64 32); 	sed -i "s/POSTGRES_PASSWORD=CHANGE_THIS_SECURE_PASSWORD/POSTGRES_PASSWORD=$$POSTGRES_PASSWORD/" .env; 	sed -i "s/SECRET_KEY_BASE=GENERATE_WITH_OPENSSL_RAND_HEX_64/SECRET_KEY_BASE=$$SECRET_KEY_BASE/" .env; 	sed -i "s/LOOMIO_HMAC_KEY=GENERATE_WITH_OPENSSL_RAND_HEX_32/LOOMIO_HMAC_KEY=$$LOOMIO_HMAC_KEY/" .env; 	sed -i "s/DEVISE_SECRET=GENERATE_WITH_OPENSSL_RAND_HEX_32/DEVISE_SECRET=$$DEVISE_SECRET/" .env; 	sed -i "s/BACKUP_ENCRYPTION_KEY=GENERATE_WITH_OPENSSL_RAND_HEX_32/BACKUP_ENCRYPTION_KEY=$$BACKUP_ENCRYPTION_KEY/" .env
	@echo "$(GREEN)✓ Production environment initialized!$(NC)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Edit .env and configure SMTP settings"
	@echo "  2. Run: make init-gdrive  (setup Google Drive)"
	@echo "  3. Run: make start"
	@echo "  4. Run: make create-admin"

init-gdrive: ## Setup Google Drive OAuth (one-time)
	@./scripts/init-gdrive.sh

##@ Cleanup

clean: ## Remove all containers, volumes, and data
	@echo "$(RED)═══════════════════════════════════════════════════$(NC)"
	@echo "$(RED)⚠  WARNING: This will DELETE ALL DATA!$(NC)"
	@echo "$(RED)═══════════════════════════════════════════════════$(NC)"
	@read -p "Type 'DELETE' to confirm: " confirm; 	if [ "$$confirm" = "DELETE" ]; then 		docker compose down -v; 		sudo rm -rf data/* production/backups/*; 		echo "$(GREEN)✓ Cleanup complete$(NC)"; 	else 		echo "Cancelled"; 	fi
