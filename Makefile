# Loomio Pi Stack - Production RAM Mode (Raspberry Pi)
SHELL := /bin/bash

.PHONY: help start stop restart status logs backup restore sync-gdrive update-images migrate create-admin health rails-console db-console init-env init-gdrive clean

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
	@printf "$(BLUE)Loomio Pi Stack - Makefile Commands$(NC)\n"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(YELLOW)<target>$(NC)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Container Management

start: ## Start all containers (auto-restores last backup if DB empty)
	@printf "$(BLUE)Starting containers...$(NC)\n"
	docker compose up -d
	@printf "$(GREEN)✓ Containers started$(NC)\n"
	@echo "Access Loomio at: http://localhost:3000"

stop: ## Stop all containers
	@printf "$(YELLOW)Stopping containers...$(NC)\n"
	docker compose stop
	@printf "$(GREEN)✓ Containers stopped$(NC)\n"

restart: ## Restart all containers
	@printf "$(YELLOW)Restarting containers...$(NC)\n"
	docker compose restart
	@printf "$(GREEN)✓ Containers restarted$(NC)\n"

rebuild: ## Rebuild and restart containers (use after code changes)
	@printf "$(BLUE)Rebuilding containers...$(NC)\n"
	docker compose build
	@printf "$(BLUE)Restarting containers...$(NC)\n"
	docker compose up -d
	@printf "$(GREEN)✓ Containers rebuilt and restarted$(NC)\n"

status: ## Show container status
	@docker compose ps

clean: ## Remove all containers, volumes, and data (WARNING: DELETES EVERYTHING)
	@printf "$(RED)═══════════════════════════════════════════════════$(NC)\n"
	@printf "$(RED)⚠  WARNING: This will DELETE ALL DATA!$(NC)\n"
	@printf "$(RED)═══════════════════════════════════════════════════$(NC)\n"
	@read -p "Type 'DELETE' to confirm: " confirm; 	if [ "$$confirm" = "DELETE" ]; then 		docker compose down -v; 		sudo rm -rf data/* data/production/backups/*; 		echo "$(GREEN)✓ Cleanup complete$(NC)"; 	else 		echo "Cancelled"; 	fi

logs: ## Show container logs (usage: make logs [SERVICE=app])
	@docker compose logs -f $(if $(SERVICE),$(SERVICE),)

##@ Manual Operations

update-images: ## Pull latest Docker images (manual)
	@printf "$(BLUE)Pulling latest images...$(NC)\n"
	docker compose pull
	@printf "$(GREEN)✓ Images updated$(NC)\n"
	@printf "$(YELLOW)Next steps:$(NC)\n"
	@echo "  1. make stop"
	@echo "  2. make start"
	@echo "  3. make migrate  (if needed)"
	@echo "  4. make backup"

migrate: ## Run database migrations (manual)
	@printf "$(BLUE)Running migrations...$(NC)\n"
	docker exec loomio-app bundle exec rake db:migrate

backup: ## Create manual database backup
	@./scripts/backup-db.sh

restore-from-gdrive: ## Complete disaster recovery (backup + uploads from GDrive)
	@./scripts/restore-from-gdrive.sh

restore: ## Restore from data/production/backups/ (interactive)
	@./scripts/restore-db-manual.sh

sync-gdrive: ## Sync backups AND uploads to Google Drive
	@./scripts/sync-to-gdrive.sh

##@ Admin Management

create-admin: ## Create admin user (prints password directly)
	@printf "$(BLUE)Creating admin user...$(NC)\n"
	@read -p "Enter email: " email; 	read -p "Enter name: " name; 	docker exec loomio-app bundle exec rails runner /scripts/ruby/create_admin.rb "$$email" "$$name"

##@ Health & Monitoring

health: ## Show container status
	@docker compose ps

##@ Console Access

rails-console: ## Open Rails console
	@docker exec -it loomio-app bundle exec rails console

db-console: ## Open PostgreSQL console
	@docker exec -it loomio-db psql -U $(shell grep POSTGRES_USER .env | cut -d '=' -f2) -d $(shell grep POSTGRES_DB .env | cut -d '=' -f2)

##@ Setup (One-Time)

install: ## Install Docker and dependencies (Raspberry Pi)
	@printf "$(BLUE)Installing Docker and dependencies...$(NC)\n"
	@if command -v docker >/dev/null 2>&1; then 		echo "$(GREEN)✓ Docker already installed$(NC)"; 	else 		echo "Installing Docker..."; 		curl -fsSL https://get.docker.com -o get-docker.sh; 		sudo sh get-docker.sh; 		rm get-docker.sh; 		sudo usermod -aG docker $$USER; 		echo "$(YELLOW)⚠ Please log out and back in for Docker permissions$(NC)"; 	fi
	@echo "Installing dependencies..."
	@sudo apt update
	@sudo apt install -y git openssl make rclone
	@printf "$(GREEN)✓ Installation complete!$(NC)\n"

init-env: ## Setup production environment (.env file)
	@printf "$(BLUE)Initializing production environment...$(NC)\n"
	@if [ -f .env ]; then 		echo "$(RED)✗ .env file already exists!$(NC)"; 		echo "Rename it first: mv .env .env.backup"; 		exit 1; 	fi
	@cp .env.production .env
	@printf "$(BLUE)Generating production secrets...$(NC)\n"
	@SECRET_KEY_BASE=$$(openssl rand -hex 64); 	LOOMIO_HMAC_KEY=$$(openssl rand -hex 32); 	DEVISE_SECRET=$$(openssl rand -hex 32); 	BACKUP_ENCRYPTION_KEY=$$(openssl rand -hex 32); 	POSTGRES_PASSWORD=$$(openssl rand -base64 32); 	sed -i "s/POSTGRES_PASSWORD=CHANGE_THIS_SECURE_PASSWORD/POSTGRES_PASSWORD=$$POSTGRES_PASSWORD/" .env; 	sed -i "s/SECRET_KEY_BASE=GENERATE_WITH_OPENSSL_RAND_HEX_64/SECRET_KEY_BASE=$$SECRET_KEY_BASE/" .env; 	sed -i "s/LOOMIO_HMAC_KEY=GENERATE_WITH_OPENSSL_RAND_HEX_32/LOOMIO_HMAC_KEY=$$LOOMIO_HMAC_KEY/" .env; 	sed -i "s/DEVISE_SECRET=GENERATE_WITH_OPENSSL_RAND_HEX_32/DEVISE_SECRET=$$DEVISE_SECRET/" .env; 	sed -i "s/BACKUP_ENCRYPTION_KEY=GENERATE_WITH_OPENSSL_RAND_HEX_32/BACKUP_ENCRYPTION_KEY=$$BACKUP_ENCRYPTION_KEY/" .env
	@printf "$(GREEN)✓ Production environment initialized!$(NC)\n"
	@echo ""
	@printf "$(YELLOW)Next steps:$(NC)\n"
	@echo "  1. Edit .env and configure SMTP settings"
	@echo "  2. Run: make init-gdrive  (setup Google Drive)"
	@echo "  3. Run: make start"
	@echo "  4. Run: make create-admin"

init-gdrive: ## Setup Google Drive OAuth (one-time)
	@./scripts/init-gdrive.sh

##@ Testing

test: ## Run all integration tests
	@./scripts/tests/run_all_tests.sh
