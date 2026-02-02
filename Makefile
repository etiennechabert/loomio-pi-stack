# Loomio Pi Stack - Production RAM Mode (Raspberry Pi)
SHELL := /bin/bash

.PHONY: help start stop restart status logs backup restore sync-gdrive pull-docker-images update-images migrate-db create-admin health rails-console db-console init-env init-gdrive destroy backup-info sidekiq-status sidekiq-retry deploy-email-worker check-updates setup-update-checker install-hourly-tasks hourly-tasks-status run-hourly-tasks install-error-report error-report-status send-error-report enable-auto-setup tunnel-start tunnel-stop tunnel-restart tunnel-status

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

destroy: ## Remove all containers, volumes, and data (WARNING: DELETES EVERYTHING)
	@printf "$(RED)═══════════════════════════════════════════════════$(NC)\n"
	@printf "$(RED)⚠  WARNING: This will DELETE ALL DATA!$(NC)\n"
	@printf "$(RED)═══════════════════════════════════════════════════$(NC)\n"
	@read -p "Type 'DELETE' to confirm: " confirm; 	if [ "$$confirm" = "DELETE" ]; then 		docker compose down -v; 		sudo rm -rf data/* data/production/backups/*; 		echo "$(GREEN)✓ Destroy complete$(NC)"; 	else 		echo "Cancelled"; 	fi

logs: ## Show container logs (usage: make logs [SERVICE=app])
	@docker compose logs -f --since 24h $(if $(SERVICE),$(SERVICE),app worker channels hocuspocus backup)

##@ Cloudflare Tunnel

tunnel-start: ## Start Cloudflare tunnel (requires CLOUDFLARE_TUNNEL_TOKEN in .env)
	@printf "$(BLUE)Starting Cloudflare tunnel...$(NC)\n"
	docker compose --profile cloudflare up -d cloudflared
	@printf "$(GREEN)✓ Cloudflare tunnel started$(NC)\n"

tunnel-stop: ## Stop Cloudflare tunnel
	@printf "$(YELLOW)Stopping Cloudflare tunnel...$(NC)\n"
	docker compose stop cloudflared
	@printf "$(GREEN)✓ Cloudflare tunnel stopped$(NC)\n"

tunnel-restart: ## Restart Cloudflare tunnel
	@printf "$(YELLOW)Restarting Cloudflare tunnel...$(NC)\n"
	docker compose restart cloudflared
	@printf "$(GREEN)✓ Cloudflare tunnel restarted$(NC)\n"

tunnel-status: ## Show Cloudflare tunnel status and logs
	@printf "$(BLUE)Cloudflare Tunnel Status$(NC)\n"
	@printf "$(BLUE)═══════════════════════════════════════════════════$(NC)\n"
	@docker compose --profile cloudflare ps cloudflared
	@echo ""
	@printf "$(BLUE)Recent logs:$(NC)\n"
	@docker compose logs --tail 20 cloudflared 2>/dev/null || echo "Tunnel not running"

##@ Manual Operations

pull-docker-images: ## Pull all Docker images from docker-compose
	@printf "$(BLUE)Pulling all images from docker-compose...$(NC)\n"
	docker compose pull
	@printf "$(GREEN)✓ All images pulled$(NC)\n"

update-images: ## Pull latest Docker images (manual)
	@printf "$(BLUE)Pulling latest images...$(NC)\n"
	docker compose pull
	@printf "$(GREEN)✓ Images updated$(NC)\n"
	@printf "$(YELLOW)Next steps:$(NC)\n"
	@echo "  1. make stop"
	@echo "  2. make start"
	@echo "  3. make migrate-db  (if needed)"
	@echo "  4. make create-backup"

migrate-db: ## Run database migrations (manual)
	@printf "$(BLUE)Running migrations...$(NC)\n"
	docker exec loomio-app bundle exec rake db:migrate

create-backup: ## Create manual backup with reason (never auto-deleted)
	@./scripts/backup-db.sh

upload-to-gdrive: ## Upload backups AND uploads to Google Drive
	@./scripts/sync-to-gdrive.sh

restore-from-gdrive: ## Download backup + uploads from Google Drive
	@./scripts/restore-from-gdrive.sh

restore-backup: ## Restore database from local backup (interactive)
	@./scripts/restore-db-manual.sh

backup-info: ## Show backup system information and available backups
	@printf "$(BLUE)Multi-Tier Backup System$(NC)\n"
	@echo ""
	@echo "Automatic Backups:"
	@echo "  • Hourly:  Hours 1-23 (48h retention)"
	@echo "  • Daily:   Midnight on days 2-31 (30d retention)"
	@echo "  • Monthly: Midnight on 1st of month (12mo retention)"
	@echo ""
	@echo "Manual Backups:"
	@echo "  • Run: make create-backup"
	@echo "  • Requires reason/description"
	@echo "  • Never automatically deleted"
	@echo ""
	@echo "All backups sync to Google Drive automatically"
	@echo ""
	@echo "=========================================="
	@echo ""
	@./scripts/list-gdrive-backups.sh

##@ Admin Management

create-admin: ## Create admin user (prints password directly)
	@printf "$(BLUE)Creating admin user...$(NC)\n"
	@read -p "Enter email: " email; 	read -p "Enter name: " name; 	docker exec loomio-app bundle exec rails runner /scripts/ruby/create_admin.rb "$$email" "$$name"

##@ Health & Monitoring

health: ## Show container status
	@docker compose ps

sidekiq-status: ## Show Sidekiq queue status and dead jobs
	@printf "$(BLUE)Sidekiq Status$(NC)\n"
	@printf "$(BLUE)═══════════════════════════════════════════════════$(NC)\n"
	@docker exec loomio-app bundle exec rails runner /scripts/ruby/sidekiq_status.rb

sidekiq-retry: ## Retry all retrying jobs immediately
	@printf "$(YELLOW)Retrying all failed jobs...$(NC)\n"
	@docker exec loomio-app bundle exec rails runner "require 'sidekiq/api'; Sidekiq::RetrySet.new.each(&:retry); puts '$(GREEN)✓ All retrying jobs have been retried$(NC)'"

##@ Console Access

rails-console: ## Open Rails console
	@docker exec -it loomio-app bundle exec rails console

db-console: ## Open PostgreSQL console
	@docker exec -it loomio-db psql -U $(shell grep POSTGRES_USER .env | cut -d '=' -f2) -d $(shell grep POSTGRES_DB .env | cut -d '=' -f2)

##@ Scheduled Tasks

enable-auto-setup: ## Enable automatic timer installation on boot
	@printf "$(BLUE)Installing bootstrap service...$(NC)\n"
	@chmod +x scripts/bootstrap-timers.sh
	@sed 's|{{PROJECT_DIR}}|$(PWD)|g' loomio-bootstrap.service | sudo tee /etc/systemd/system/loomio-bootstrap.service > /dev/null
	@sudo systemctl daemon-reload
	@sudo systemctl enable loomio-bootstrap.service
	@printf "$(GREEN)✓ Bootstrap service installed$(NC)\n"
	@echo ""
	@echo "The following timers will be auto-installed on boot if missing:"
	@echo "  • loomio-hourly.timer (maintenance, poll closing)"
	@echo "  • loomio-error-report.timer (daily error digest)"
	@echo ""
	@echo "Run now: sudo systemctl start loomio-bootstrap.service"

install-hourly-tasks: ## Install systemd timer for hourly maintenance tasks
	@printf "$(BLUE)Installing hourly tasks timer...$(NC)\n"
	@chmod +x scripts/run-hourly-tasks.sh
	@sudo cp loomio-hourly.timer /etc/systemd/system/
	@sed 's|{{PROJECT_DIR}}|$(PWD)|g' loomio-hourly.service | sudo tee /etc/systemd/system/loomio-hourly.service > /dev/null
	@sudo systemctl daemon-reload
	@sudo systemctl enable loomio-hourly.timer
	@sudo systemctl start loomio-hourly.timer
	@printf "$(GREEN)✓ Hourly tasks timer installed and started$(NC)\n"
	@echo ""
	@echo "This timer runs maintenance tasks every hour including:"
	@echo "  • Closing expired polls"
	@echo "  • Sending 'closing soon' notifications"
	@echo "  • Task reminders"
	@echo "  • Email routing"

hourly-tasks-status: ## Show hourly tasks timer status
	@printf "$(BLUE)Hourly Tasks Timer Status$(NC)\n"
	@printf "$(BLUE)═══════════════════════════════════════════════════$(NC)\n"
	@sudo systemctl status loomio-hourly.timer --no-pager
	@echo ""
	@printf "$(BLUE)Next scheduled run:$(NC)\n"
	@sudo systemctl list-timers loomio-hourly.timer --no-pager

run-hourly-tasks: ## Manually trigger hourly tasks (for testing)
	@printf "$(BLUE)Running hourly tasks manually...$(NC)\n"
	@sudo systemctl start loomio-hourly.service
	@printf "$(GREEN)✓ Hourly tasks triggered$(NC)\n"
	@echo "Check logs with: sudo journalctl -u loomio-hourly.service -f"

install-error-report: ## Install daily error report email
	@printf "$(BLUE)Installing daily error report...$(NC)\n"
	@chmod +x scripts/send-error-report.sh
	@sudo cp loomio-error-report.timer /etc/systemd/system/
	@sed 's|{{PROJECT_DIR}}|$(PWD)|g' loomio-error-report.service | sudo tee /etc/systemd/system/loomio-error-report.service > /dev/null
	@sudo systemctl daemon-reload
	@sudo systemctl enable loomio-error-report.timer
	@sudo systemctl start loomio-error-report.timer
	@printf "$(GREEN)✓ Daily error report installed$(NC)\n"
	@echo ""
	@echo "Report will be sent daily at 8:00 AM to: $$(grep ALERT_EMAIL .env | cut -d '=' -f2)"
	@echo "Only errors/exceptions will trigger an email (no email on clean days)"
	@echo "Check status: make error-report-status"
	@echo "Send test report: make send-error-report"

error-report-status: ## Show error report timer status
	@printf "$(BLUE)Error Report Timer Status$(NC)\n"
	@printf "$(BLUE)═══════════════════════════════════════════════════$(NC)\n"
	@sudo systemctl status loomio-error-report.timer --no-pager
	@echo ""
	@printf "$(BLUE)Next scheduled run:$(NC)\n"
	@sudo systemctl list-timers loomio-error-report.timer --no-pager

send-error-report: ## Manually send error report (for testing)
	@printf "$(BLUE)Sending error report...$(NC)\n"
	@./scripts/send-error-report.sh
	@printf "$(GREEN)✓ Error report sent$(NC)\n"

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
	@echo "  2. Run: make enable-auto-setup  (auto-install timers on boot)"
	@echo "  3. Run: make init-gdrive  (setup Google Drive - optional)"
	@echo "  4. Run: make start"
	@echo "  5. Run: make create-admin"

init-gdrive: ## Setup Google Drive OAuth (one-time)
	@./scripts/init-gdrive.sh

##@ Email Worker (Incoming Email)

deploy-email-worker: ## Deploy Cloudflare Email Worker for incoming email
	@./scripts/deploy-email-worker.sh

##@ Update Management

check-updates: ## Check for Docker image updates (no auto-install)
	@printf "$(BLUE)Checking for Docker image updates...$(NC)\n"
	@chmod +x ./scripts/check-updates.sh
	@./scripts/check-updates.sh

setup-update-checker: ## Setup daily update checker with email notifications
	@printf "$(BLUE)Setting up daily update checker...$(NC)\n"
	@chmod +x ./scripts/check-updates.sh
	@printf "$(YELLOW)Creating systemd timer for daily checks...$(NC)\n"
	@echo "Add this to your crontab (run: crontab -e):"
	@echo ""
	@echo "# Check for Loomio updates daily at 9am"
	@echo "0 9 * * * cd $(PWD) && ./scripts/check-updates.sh >> data/production/logs/update-check.log 2>&1"
	@echo ""
	@printf "$(GREEN)✓ Update checker configured$(NC)\n"
	@echo "Email notifications will be sent to: $${ALERT_EMAIL}"

##@ Testing

test: ## Run all integration tests
	@./scripts/tests/run_all_tests.sh
