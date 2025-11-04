.PHONY: help install init-env-dev init-env-prod check-env init start stop restart down status logs backup restore update clean enable-autostart disable-autostart check-config health reset-db auto-create-admin create-admin promote-user list-users rails-console db-console init-gdrive sync-files restore-files list-backups info first-time-setup

# Default target
.DEFAULT_GOAL := help

# Colors for output
BLUE := \033[0;34m
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m # No Color

##@ General

help: ## Display this help message
	@echo "$(BLUE)Loomio Pi Stack - Makefile Commands$(NC)"
	@echo ""
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make $(YELLOW)<target>$(NC)\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  $(GREEN)%-20s$(NC) %s\n", $$1, $$2 } /^##@/ { printf "\n$(BLUE)%s$(NC)\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Setup & Installation

install: ## Install Docker and dependencies
	@echo "$(BLUE)Installing Docker and dependencies...$(NC)"
	@if command -v docker >/dev/null 2>&1; then \
		echo "$(GREEN)✓ Docker already installed$(NC)"; \
	else \
		echo "Installing Docker..."; \
		curl -fsSL https://get.docker.com -o get-docker.sh; \
		sudo sh get-docker.sh; \
		rm get-docker.sh; \
		sudo usermod -aG docker $$USER; \
		echo "$(YELLOW)⚠ Please log out and back in for Docker permissions$(NC)"; \
	fi
	@echo "Installing additional dependencies..."
	@sudo apt update
	@sudo apt install -y git openssl python3 python3-pip make
	@echo "$(GREEN)✓ Installation complete!$(NC)"

init-env-dev: ## Setup development environment (creates .env from .env.development)
	@echo "$(BLUE)Initializing DEVELOPMENT environment...$(NC)"
	@if [ -f .env ]; then \
		echo "$(RED)✗ .env file already exists!$(NC)"; \
		echo ""; \
		echo "$(YELLOW)To avoid overwriting your configuration:$(NC)"; \
		echo "  1. Rename existing file:  mv .env .env.backup"; \
		echo "  2. Or remove it:          rm .env"; \
		echo "  3. Then run:              make init-env-dev"; \
		echo ""; \
		exit 1; \
	fi
	@cp .env.development .env
	@echo "$(GREEN)✓ Development environment initialized!$(NC)"
	@echo ""
	@echo "$(BLUE)Configuration:$(NC)"
	@echo "  Environment: DEVELOPMENT"
	@echo "  URL: http://localhost:3000"
	@echo "  Database: loomio_development"
	@echo "  SSL: Disabled"
	@echo ""
	@echo "$(GREEN)Next steps:$(NC)"
	@echo "  1. Run: make init"
	@echo "  2. Run: make start"
	@echo "  3. Run: make add-admin  (to create your first admin user)"

init-env-prod: ## Setup production environment (creates .env from .env.production with generated secrets)
	@echo "$(BLUE)Initializing PRODUCTION environment...$(NC)"
	@if [ -f .env ]; then \
		echo "$(RED)✗ .env file already exists!$(NC)"; \
		echo ""; \
		echo "$(YELLOW)To avoid overwriting your configuration:$(NC)"; \
		echo "  1. Rename existing file:  mv .env .env.backup"; \
		echo "  2. Or remove it:          rm .env"; \
		echo "  3. Then run:              make init-env-prod"; \
		echo ""; \
		exit 1; \
	fi
	@cp .env.production .env
	@echo ""
	@echo "$(BLUE)Generating production secrets...$(NC)"
	@SECRET_KEY_BASE=$$(openssl rand -hex 64); \
	LOOMIO_HMAC_KEY=$$(openssl rand -hex 32); \
	DEVISE_SECRET=$$(openssl rand -hex 32); \
	BACKUP_ENCRYPTION_KEY=$$(openssl rand -hex 32); \
	POSTGRES_PASSWORD=$$(openssl rand -base64 32); \
	sed -i.bak "s/POSTGRES_PASSWORD=CHANGE_THIS_SECURE_PASSWORD/POSTGRES_PASSWORD=$$POSTGRES_PASSWORD/" .env; \
	sed -i.bak "s/SECRET_KEY_BASE=GENERATE_WITH_OPENSSL_RAND_HEX_64/SECRET_KEY_BASE=$$SECRET_KEY_BASE/" .env; \
	sed -i.bak "s/LOOMIO_HMAC_KEY=GENERATE_WITH_OPENSSL_RAND_HEX_32/LOOMIO_HMAC_KEY=$$LOOMIO_HMAC_KEY/" .env; \
	sed -i.bak "s/DEVISE_SECRET=GENERATE_WITH_OPENSSL_RAND_HEX_32/DEVISE_SECRET=$$DEVISE_SECRET/" .env; \
	sed -i.bak "s/BACKUP_ENCRYPTION_KEY=GENERATE_WITH_OPENSSL_RAND_HEX_32/BACKUP_ENCRYPTION_KEY=$$BACKUP_ENCRYPTION_KEY/" .env; \
	rm .env.bak; \
	echo "$(GREEN)✓ Secrets generated!$(NC)"
	@echo ""
	@echo "$(YELLOW)⚠ IMPORTANT: Edit .env and configure:$(NC)"
	@echo "  - CANONICAL_HOST (your domain)"
	@echo "  - SUPPORT_EMAIL"
	@echo "  - SMTP settings (email server)"
	@echo "  - GDRIVE_CREDENTIALS and GDRIVE_FOLDER_ID (for backups)"
	@echo ""
	@echo "$(BLUE)Edit with: nano .env$(NC)"
	@echo ""
	@echo "$(GREEN)After editing:$(NC)"
	@echo "  1. Run: make init"
	@echo "  2. Run: make start"
	@echo "  3. Run: make add-admin  (to create your first admin user)"

check-env:
	@if [ ! -f .env ]; then \
		echo "$(RED)✗ .env file not found!$(NC)"; \
		echo "$(YELLOW)Run either:$(NC)"; \
		echo "  make init-env-dev  (for development)"; \
		echo "  make init-env-prod (for production)"; \
		exit 1; \
	fi

check-config: ## Validate configuration
	@echo "$(BLUE)Validating configuration...$(NC)"
	@docker compose config > /dev/null && echo "$(GREEN)✓ docker-compose.yml is valid$(NC)" || echo "$(RED)✗ docker-compose.yml has errors$(NC)"
	@if [ -f .env ]; then \
		echo "$(GREEN)✓ .env exists$(NC)"; \
		if grep -q "CHANGE_THIS" .env 2>/dev/null; then \
			echo "$(YELLOW)⚠ Warning: Found default passwords in .env$(NC)"; \
		fi; \
		if grep -q "GENERATE_WITH" .env 2>/dev/null; then \
			echo "$(YELLOW)⚠ Warning: Some secrets not generated in .env$(NC)"; \
		fi; \
	else \
		echo "$(RED)✗ .env not found$(NC)"; \
	fi

##@ Database Management

init: check-env ## Initialize database (first time only)
	@echo "$(BLUE)Building services...$(NC)"
	@mkdir -p backups
	docker compose build backup
	@echo "$(BLUE)Pulling images...$(NC)"
	docker compose pull
	@echo "$(BLUE)Starting database...$(NC)"
	docker compose up -d db redis
	@echo "Waiting for database to be ready..."
	@sleep 30
	@echo "$(BLUE)Initializing database schema...$(NC)"
	docker compose run --rm app rake db:setup
	@echo "$(GREEN)✓ Database initialized!$(NC)"
	@echo ""
	@echo "$(GREEN)Ready to start! Run: make start$(NC)"

reset-db: ## Reset database to empty state (DESTRUCTIVE!)
	@echo "$(RED)⚠⚠⚠ WARNING: This will PERMANENTLY DELETE all data! ⚠⚠⚠$(NC)"
	@echo "$(YELLOW)This operation will:$(NC)"
	@echo "  - Stop all services"
	@echo "  - Remove database volume (all data lost)"
	@echo "  - All groups, discussions, and users will be lost"
	@echo ""
	@read -p "Type 'yes' to confirm: " confirm; \
	if [ "$$confirm" != "yes" ]; then \
		echo "$(GREEN)✓ Operation cancelled$(NC)"; \
		exit 0; \
	fi
	@echo ""
	@echo "$(BLUE)Stopping all services...$(NC)"
	@docker compose down
	@echo "$(BLUE)Removing database volume...$(NC)"
	@docker volume rm $$(docker volume ls -q -f name=db-data) 2>/dev/null || echo "No db-data volume found"
	@echo "$(GREEN)✓ Database reset complete!$(NC)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(NC)"
	@echo "  1. Run 'make init' to initialize fresh database"
	@echo "  2. Run 'make start' to start services"

##@ Service Management

preflight-check:
	@if grep -q "RAILS_ENV=production" .env 2>/dev/null; then \
		echo "$(BLUE)Running production preflight checks...$(NC)"; \
		set -a; . .env; set +a; \
		ERRORS=0; \
		\
		echo "$(BLUE)Checking critical configuration...$(NC)"; \
		\
		if [ "$$RAILS_ENV" != "production" ]; then \
			echo "$(RED)✗ RAILS_ENV must be 'production'$(NC)"; \
			ERRORS=$$((ERRORS + 1)); \
		else \
			echo "$(GREEN)✓ RAILS_ENV set to production$(NC)"; \
		fi; \
		\
		if [ -z "$$CANONICAL_HOST" ] || echo "$$CANONICAL_HOST" | grep -qE '(localhost|example\.com|127\.0\.0\.1)'; then \
			echo "$(RED)✗ CANONICAL_HOST must be set to your actual domain$(NC)"; \
			ERRORS=$$((ERRORS + 1)); \
		else \
			echo "$(GREEN)✓ CANONICAL_HOST configured: $$CANONICAL_HOST$(NC)"; \
		fi; \
		\
		if [ "$$FORCE_SSL" != "true" ]; then \
			echo "$(RED)✗ FORCE_SSL must be enabled (true) for production$(NC)"; \
			ERRORS=$$((ERRORS + 1)); \
		else \
			echo "$(GREEN)✓ SSL enforcement enabled$(NC)"; \
		fi; \
		\
		if [ -z "$$SECRET_KEY_BASE" ] || echo "$$SECRET_KEY_BASE" | grep -qE '(GENERATE|test|dev|example)'; then \
			echo "$(RED)✗ SECRET_KEY_BASE must be a secure random value$(NC)"; \
			ERRORS=$$((ERRORS + 1)); \
		else \
			echo "$(GREEN)✓ SECRET_KEY_BASE configured$(NC)"; \
		fi; \
		\
		if [ -z "$$LOOMIO_HMAC_KEY" ] || echo "$$LOOMIO_HMAC_KEY" | grep -qE '(GENERATE|test|dev|example)'; then \
			echo "$(RED)✗ LOOMIO_HMAC_KEY must be a secure random value$(NC)"; \
			ERRORS=$$((ERRORS + 1)); \
		else \
			echo "$(GREEN)✓ LOOMIO_HMAC_KEY configured$(NC)"; \
		fi; \
		\
		if [ -z "$$DEVISE_SECRET" ] || echo "$$DEVISE_SECRET" | grep -qE '(GENERATE|test|dev|example)'; then \
			echo "$(RED)✗ DEVISE_SECRET must be a secure random value$(NC)"; \
			ERRORS=$$((ERRORS + 1)); \
		else \
			echo "$(GREEN)✓ DEVISE_SECRET configured$(NC)"; \
		fi; \
		\
		if [ -z "$$BACKUP_ENCRYPTION_KEY" ] || echo "$$BACKUP_ENCRYPTION_KEY" | grep -qE '(GENERATE|test|dev|example)'; then \
			echo "$(RED)✗ BACKUP_ENCRYPTION_KEY must be a secure random value$(NC)"; \
			ERRORS=$$((ERRORS + 1)); \
		else \
			echo "$(GREEN)✓ Backup encryption configured$(NC)"; \
		fi; \
		\
		if [ -z "$$SMTP_SERVER" ] || echo "$$SMTP_SERVER" | grep -qE '(example\.com|localhost)'; then \
			echo "$(YELLOW)⚠ WARNING: SMTP not configured - email features will not work$(NC)"; \
		else \
			echo "$(GREEN)✓ SMTP server configured: $$SMTP_SERVER$(NC)"; \
		fi; \
		\
		if [ -z "$$POSTGRES_PASSWORD" ] || echo "$$POSTGRES_PASSWORD" | grep -qE '(CHANGE|password|test|dev)'; then \
			echo "$(RED)✗ POSTGRES_PASSWORD must be a secure password$(NC)"; \
			ERRORS=$$((ERRORS + 1)); \
		else \
			echo "$(GREEN)✓ Database password configured$(NC)"; \
		fi; \
		\
		echo ""; \
		if [ $$ERRORS -gt 0 ]; then \
			echo "$(RED)✗ Production preflight failed with $$ERRORS critical error(s)$(NC)"; \
			echo "$(YELLOW)Fix the errors above before starting production$(NC)"; \
			exit 1; \
		else \
			echo "$(GREEN)✓ All critical checks passed$(NC)"; \
		fi; \
	fi

start: check-env preflight-check ## Start all services
	@echo "$(BLUE)Starting Loomio stack...$(NC)"
	@set -a; . ./.env; set +a; \
	if grep -q "RAILS_ENV=production" .env 2>/dev/null; then \
		echo "$(YELLOW)Production Mode: Using RAM mode for database and Redis$(NC)"; \
		docker compose -f docker-compose.yml -f docker-compose.ram.yml up -d; \
		echo "$(BLUE)Initializing RAM database from Google Drive...$(NC)"; \
		./scripts/init-ram.sh; \
	else \
		echo "$(BLUE)Development Mode: Using disk-based storage$(NC)"; \
		docker compose up -d; \
	fi
	@echo "$(GREEN)✓ Loomio stack started!$(NC)"
	@echo ""
	@set -a; . ./.env; set +a; \
	if grep -q "RAILS_ENV=production" .env 2>/dev/null; then \
		echo "$(YELLOW)⚠ RAM Mode Active (Production):$(NC)"; \
		echo "  - Database and Redis in RAM"; \
		echo "  - Backups in RAM → Google Drive"; \
		echo "  - Monitor usage: make ram-usage"; \
		echo ""; \
		echo "$(BLUE)Access Loomio at:$(NC)"; \
		echo "  Web Interface:  https://$$CANONICAL_HOST"; \
	else \
		echo "$(BLUE)Access Loomio at:$(NC)"; \
		echo "  Web Interface:  http://localhost:3000"; \
		echo "  Adminer:        http://localhost:8081"; \
	fi
	@echo "  Netdata:        http://$(shell hostname -I | awk '{print $$1}'):19999"
	@echo ""
	@echo "$(YELLOW)View logs: make logs$(NC)"

stop: ## Stop all services
	@set -a; . ./.env 2>/dev/null; set +a; \
	if grep -q "RAILS_ENV=production" .env 2>/dev/null; then \
		echo "$(YELLOW)⚠ Production/RAM Mode: Creating backup before stopping...$(NC)"; \
		$(MAKE) db-backup; \
	fi
	@echo "$(BLUE)Stopping Loomio stack...$(NC)"
	@docker compose stop
	@echo "$(GREEN)✓ Services stopped$(NC)"

restart: ## Restart all services
	@set -a; . ./.env 2>/dev/null; set +a; \
	if grep -q "RAILS_ENV=production" .env 2>/dev/null; then \
		echo "$(YELLOW)⚠ Production/RAM Mode: Creating backup before restart...$(NC)"; \
		$(MAKE) db-backup; \
		echo "$(BLUE)Restarting with RAM mode...$(NC)"; \
		docker compose -f docker-compose.yml -f docker-compose.ram.yml restart; \
		echo "$(BLUE)Restoring database from Google Drive...$(NC)"; \
		./scripts/init-ram.sh; \
	else \
		echo "$(BLUE)Restarting Loomio stack...$(NC)"; \
		docker compose restart; \
	fi
	@echo "$(GREEN)✓ Services restarted$(NC)"

down: ## Stop and remove all containers
	@set -a; . ./.env 2>/dev/null; set +a; \
	if grep -q "RAILS_ENV=production" .env 2>/dev/null; then \
		echo "$(YELLOW)⚠ Production/RAM Mode: All data in RAM will be LOST!$(NC)"; \
		echo "$(YELLOW)Creating final backup...$(NC)"; \
		$(MAKE) db-backup || true; \
	fi
	@echo "$(RED)Stopping and removing all containers...$(NC)"
	@docker compose down
	@echo "$(GREEN)✓ Containers removed$(NC)"

status: ## Show status of all services
	@echo "$(BLUE)Loomio Stack Status:$(NC)"
	@docker compose ps

logs: ## Show logs (Usage: make logs [SERVICE=app])
	@if [ -n "$(SERVICE)" ]; then \
		docker compose logs -f $(SERVICE); \
	else \
		docker compose logs -f; \
	fi

##@ Monitoring

ram-usage: ## Show RAM usage for database and Redis (useful in RAM mode)
	@echo "$(BLUE)RAM Usage (Database & Redis):$(NC)"
	@echo ""
	@echo "$(YELLOW)Database:$(NC)"
	@docker compose exec db du -sh /var/lib/postgresql/data 2>/dev/null || echo "  Database not running"
	@echo ""
	@echo "$(YELLOW)Redis:$(NC)"
	@docker compose exec redis du -sh /data 2>/dev/null || echo "  Redis not running"
	@echo ""
	@echo "$(BLUE)System Memory:$(NC)"
	@free -h | grep -E '(Mem|Swap)'

ram-stats: ## Show live resource stats for all containers (Ctrl+C to exit)
	@echo "$(BLUE)Live Container Stats (RAM, CPU, Network)$(NC)"
	@echo "$(YELLOW)Press Ctrl+C to exit$(NC)"
	@echo ""
	@docker stats

##@ Backup & Restore

db-backup: check-env ## Create encrypted database backup (./data/db_backup/)
	@echo "$(BLUE)Creating database backup...$(NC)"
	@mkdir -p data/db_backup
	@docker compose exec backup python3 /app/backup.py
	@echo "$(GREEN)✓ Database backup complete!$(NC)"
	@echo ""
	@$(MAKE) list-backups

sync-data: check-env ## Sync all data (DB backups + uploads) to Google Drive
	@echo "$(BLUE)Syncing data to Google Drive...$(NC)"
	@docker compose exec app bash /scripts/sync-data.sh

restore-db: check-env ## Download and restore latest database backup from Google Drive
	@./scripts/restore-db.sh

restore-uploads: check-env ## Download and restore all uploads from Google Drive
	@./scripts/restore-uploads.sh

list-backups: ## List all local database backups
	@echo "$(BLUE)Database Backups:$(NC)"
	@ls -lh data/db_backup/*.sql* 2>/dev/null || echo "No backups found"

##@ User Management

add-user: check-env ## Create a new user with auto-generated password
	@echo "$(BLUE)═══════════════════════════════════════$(NC)"
	@echo "$(BLUE)         Create Loomio User            $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════$(NC)"
	@echo ""
	@read -p "Email address: " email; \
	read -p "Display name: " name; \
	if [ -z "$$email" ] || [ -z "$$name" ]; then \
		echo "$(RED)✗ Email and name are required!$(NC)"; \
		exit 1; \
	fi; \
	if ! echo "$$email" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$$'; then \
		echo "$(RED)✗ Invalid email format!$(NC)"; \
		exit 1; \
	fi; \
	PASSWORD=$$(openssl rand -base64 18 | tr -d '/+=' | head -c 16); \
	echo ""; \
	echo "$(BLUE)Creating user...$(NC)"; \
	docker compose run --rm app rails runner " \
		begin \
			user = User.create!( \
				email: '$$email', \
				name: '$$name', \
				password: '$$PASSWORD', \
				password_confirmation: '$$PASSWORD', \
				email_verified: true, \
				is_admin: false \
			); \
			puts '✓ User created successfully'; \
		rescue => e \
			puts '✗ Error: ' + e.message; \
			exit 1; \
		end \
	" && { \
		echo ""; \
		echo "$(GREEN)═══════════════════════════════════════$(NC)"; \
		echo "$(GREEN)   ✓ User Created Successfully!        $(NC)"; \
		echo "$(GREEN)═══════════════════════════════════════$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Credentials:$(NC)"; \
		echo "  Email:    $$email"; \
		echo "  Name:     $$name"; \
		echo "  Password: $$PASSWORD"; \
		echo ""; \
		echo "$(YELLOW)⚠ IMPORTANT: Save this password securely!$(NC)"; \
		echo "$(YELLOW)   It will not be displayed again.$(NC)"; \
		echo ""; \
	} || { \
		echo ""; \
		echo "$(RED)✗ Failed to create user$(NC)"; \
		exit 1; \
	}

add-admin: check-env ## Create an admin user with auto-generated password
	@echo "$(BLUE)═══════════════════════════════════════$(NC)"
	@echo "$(BLUE)        Create Loomio Admin User        $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════$(NC)"
	@echo ""
	@read -p "Email address: " email; \
	read -p "Display name: " name; \
	if [ -z "$$email" ] || [ -z "$$name" ]; then \
		echo "$(RED)✗ Email and name are required!$(NC)"; \
		exit 1; \
	fi; \
	if ! echo "$$email" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$$'; then \
		echo "$(RED)✗ Invalid email format!$(NC)"; \
		exit 1; \
	fi; \
	PASSWORD=$$(openssl rand -base64 18 | tr -d '/+=' | head -c 16); \
	echo ""; \
	echo "$(BLUE)Creating admin user...$(NC)"; \
	docker compose run --rm app rails runner " \
		begin \
			user = User.create!( \
				email: '$$email', \
				name: '$$name', \
				password: '$$PASSWORD', \
				password_confirmation: '$$PASSWORD', \
				email_verified: true, \
				is_admin: true \
			); \
			puts '✓ Admin user created successfully'; \
		rescue => e \
			puts '✗ Error: ' + e.message; \
			exit 1; \
		end \
	" && { \
		echo ""; \
		echo "$(GREEN)═══════════════════════════════════════$(NC)"; \
		echo "$(GREEN)  ✓ Admin User Created Successfully!  $(NC)"; \
		echo "$(GREEN)═══════════════════════════════════════$(NC)"; \
		echo ""; \
		echo "$(YELLOW)Admin Credentials:$(NC)"; \
		echo "  Email:    $$email"; \
		echo "  Name:     $$name"; \
		echo "  Password: $$PASSWORD"; \
		echo ""; \
		echo "$(YELLOW)⚠ IMPORTANT: Save this password securely!$(NC)"; \
		echo "$(YELLOW)   It will not be displayed again.$(NC)"; \
		echo ""; \
	} || { \
		echo ""; \
		echo "$(RED)✗ Failed to create admin user$(NC)"; \
		exit 1; \
	}

list-users: check-env ## List all users
	@echo "$(BLUE)Loomio Users:$(NC)"
	@docker compose run --rm app rails runner " \
		User.order(:created_at).each do |u| \
			admin_label = u.is_admin ? ' [ADMIN]' : ''; \
			verified = u.email_verified ? '✓' : '✗'; \
			puts \"#{verified} #{u.email} - #{u.name}#{admin_label}\"; \
		end \
	"

##@ Console Access

rails-console: check-env ## Open Rails console
	@echo "$(BLUE)Opening Rails console...$(NC)"
	@docker compose run --rm app rails c

db-console: check-env ## Open PostgreSQL console
	@echo "$(BLUE)Opening database console...$(NC)"
	@set -a; . ./.env; set +a; \
	DB_NAME=$${POSTGRES_DB:-loomio_production}; \
	docker compose exec db psql -U loomio -d $$DB_NAME

##@ Maintenance

update: ## Update all containers
	@echo "$(BLUE)Updating all containers...$(NC)"
	@docker compose pull
	@docker compose up -d
	@echo "$(BLUE)Running database migrations...$(NC)"
	@docker compose run --rm app rake db:migrate
	@echo "$(GREEN)✓ Update complete$(NC)"

clean: ## Clean up Docker resources
	@echo "$(BLUE)Cleaning up Docker resources...$(NC)"
	@docker system prune -f
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

health: ## Check health of all services
	@echo "$(BLUE)Running health checks...$(NC)"
	@./scripts/watchdog/health-monitor.sh

##@ Systemd Integration

enable-autostart: check-env ## Enable automatic startup on boot
	@echo "$(BLUE)Enabling autostart...$(NC)"
	@if grep -q "RAILS_ENV=production" .env 2>/dev/null; then \
		echo "$(YELLOW)⚠ Production environment detected - running preflight checks...$(NC)"; \
		$(MAKE) preflight-check || exit 1; \
	fi
	@sudo cp loomio.service /etc/systemd/system/
	@sudo cp loomio-watchdog.service /etc/systemd/system/
	@sudo cp loomio-watchdog.timer /etc/systemd/system/
	@sudo sed -i "s|/home/pi/loomio-pi-stack|$(shell pwd)|g" /etc/systemd/system/loomio.service
	@sudo sed -i "s|/home/pi/loomio-pi-stack|$(shell pwd)|g" /etc/systemd/system/loomio-watchdog.service
	@sudo systemctl daemon-reload
	@sudo systemctl enable loomio.service
	@sudo systemctl enable loomio-watchdog.timer
	@sudo systemctl start loomio-watchdog.timer
	@echo "$(GREEN)✓ Autostart enabled!$(NC)"
	@echo "$(YELLOW)Loomio will start automatically on boot$(NC)"

disable-autostart: ## Disable automatic startup on boot
	@echo "$(BLUE)Disabling autostart...$(NC)"
	@sudo systemctl disable loomio.service 2>/dev/null || true
	@sudo systemctl disable loomio-watchdog.timer 2>/dev/null || true
	@sudo systemctl stop loomio-watchdog.timer 2>/dev/null || true
	@echo "$(GREEN)✓ Autostart disabled$(NC)"

##@ Information

info: ## Show system and service information
	@echo "$(BLUE)Loomio Pi Stack Information$(NC)"
	@echo ""
	@echo "$(BLUE)System:$(NC)"
	@echo "  Hostname:       $(shell hostname)"
	@echo "  IP Address:     $(shell hostname -I | awk '{print $$1}')"
	@echo ""
	@echo "$(BLUE)Services:$(NC)"
	@docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@set -a; . ./.env 2>/dev/null; set +a; \
	if grep -q "RAILS_ENV=production" .env 2>/dev/null; then \
		echo "$(BLUE)Service URLs:$(NC)"; \
		echo "  Loomio:         https://$$CANONICAL_HOST"; \
	else \
		echo "$(BLUE)Service URLs:$(NC)"; \
		echo "  Loomio:         http://$(shell hostname -I | awk '{print $$1}'):3000"; \
		echo "  Adminer:        http://$(shell hostname -I | awk '{print $$1}'):8081"; \
	fi
	@echo "  Netdata:        http://$(shell hostname -I | awk '{print $$1}'):19999"
	@echo ""
	@echo "$(BLUE)Container Versions:$(NC)"
	@docker compose images
