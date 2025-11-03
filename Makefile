.PHONY: help install setup init start stop restart down status logs backup restore update clean enable-autostart disable-autostart check-config health first-time-setup dev-setup prod-setup dev prod dev-init prod-init dev-logs prod-logs dev-status prod-status

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

check-env:
	@if [ ! -f .env ]; then \
		echo "$(RED)✗ .env file not found!$(NC)"; \
		echo "$(YELLOW)Run: make setup$(NC)"; \
		exit 1; \
	fi

setup: ## Create .env and generate secrets
	@echo "$(BLUE)Setting up Loomio Pi Stack...$(NC)"
	@if [ -f .env ]; then \
		echo "$(RED)✗ .env file already exists!$(NC)"; \
		echo ""; \
		echo "$(YELLOW)To avoid overwriting your configuration, please:$(NC)"; \
		echo "  1. Rename existing file:  mv .env .env.backup"; \
		echo "  2. Or remove it:          rm .env"; \
		echo "  3. Then run:              make setup"; \
		echo ""; \
		exit 1; \
	fi
	@cp .env.example .env
	@echo ""
	@echo "$(BLUE)Generating secrets...$(NC)"
	@SECRET_KEY_BASE=$$(openssl rand -hex 64); \
	LOOMIO_HMAC_KEY=$$(openssl rand -hex 32); \
	DEVISE_SECRET=$$(openssl rand -hex 32); \
	BACKUP_ENCRYPTION_KEY=$$(openssl rand -hex 32); \
	POSTGRES_PASSWORD=$$(openssl rand -base64 32); \
	LOOMIO_ADMIN_PASSWORD=$$(openssl rand -base64 24); \
	sed -i.bak "s/SECRET_KEY_BASE=generate-with-openssl-rand-hex-64/SECRET_KEY_BASE=$$SECRET_KEY_BASE/" .env; \
	sed -i.bak "s/LOOMIO_HMAC_KEY=generate-with-openssl-rand-hex-32/LOOMIO_HMAC_KEY=$$LOOMIO_HMAC_KEY/" .env; \
	sed -i.bak "s/DEVISE_SECRET=generate-with-openssl-rand-hex-32/DEVISE_SECRET=$$DEVISE_SECRET/" .env; \
	sed -i.bak "s/BACKUP_ENCRYPTION_KEY=generate-with-openssl-rand-hex-32/BACKUP_ENCRYPTION_KEY=$$BACKUP_ENCRYPTION_KEY/" .env; \
	sed -i.bak "s|POSTGRES_PASSWORD=change-this-secure-password|POSTGRES_PASSWORD=$$POSTGRES_PASSWORD|" .env; \
	sed -i.bak "s|LOOMIO_ADMIN_EMAIL=|LOOMIO_ADMIN_EMAIL=admin@loomio.local|" .env; \
	sed -i.bak "s|LOOMIO_ADMIN_PASSWORD=|LOOMIO_ADMIN_PASSWORD=$$LOOMIO_ADMIN_PASSWORD|" .env; \
	rm .env.bak; \
	echo "$(GREEN)✓ Secrets generated!$(NC)"; \
	echo ""; \
	echo "$(GREEN)✓ Admin credentials generated:$(NC)"; \
	echo "  Email: admin@loomio.local"; \
	echo "  Password: $$LOOMIO_ADMIN_PASSWORD"
	@echo ""
	@echo "$(YELLOW)⚠ IMPORTANT: Edit .env and configure:$(NC)"
	@echo "  - CANONICAL_HOST (your domain)"
	@echo "  - SUPPORT_EMAIL"
	@echo "  - SMTP settings (email server)"
	@echo ""
	@echo "$(BLUE)Edit with: nano .env$(NC)"
	@echo ""
	@echo "$(GREEN)After editing .env, run: make init$(NC)"

check-config: ## Validate configuration
	@echo "$(BLUE)Validating configuration...$(NC)"
	@docker compose config > /dev/null && echo "$(GREEN)✓ docker-compose.yml is valid$(NC)" || echo "$(RED)✗ docker-compose.yml has errors$(NC)"
	@if [ -f .env ]; then \
		echo "$(GREEN)✓ .env exists$(NC)"; \
		if grep -q "change-this" .env 2>/dev/null; then \
			echo "$(YELLOW)⚠ Warning: Found default passwords in .env$(NC)"; \
		fi; \
		if grep -q "generate-with" .env 2>/dev/null; then \
			echo "$(YELLOW)⚠ Warning: Some secrets not generated in .env$(NC)"; \
		fi; \
	else \
		echo "$(RED)✗ .env not found$(NC)"; \
	fi

##@ Environment-Specific Setup

dev-setup: ## Setup for development (localhost, Rails dev mode)
	@echo "$(BLUE)Setting up DEVELOPMENT environment...$(NC)"
	@if [ -f .env ]; then \
		echo "$(RED)✗ .env file already exists!$(NC)"; \
		echo ""; \
		echo "$(YELLOW)To avoid overwriting your configuration, please:$(NC)"; \
		echo "  1. Rename existing file:  mv .env .env.backup"; \
		echo "  2. Or remove it:          rm .env"; \
		echo "  3. Then run:              make dev-setup"; \
		echo ""; \
		exit 1; \
	fi
	@cp .env.development .env
	@echo "$(GREEN)✓ Development environment configured!$(NC)"
	@echo ""
	@echo "$(BLUE)Configuration:$(NC)"
	@echo "  Environment: DEVELOPMENT"
	@echo "  URL: http://localhost:3000"
	@echo "  Database: loomio_development"
	@echo "  SSL: Disabled"
	@echo "  Admin: admin@localhost / admin123"
	@echo ""
	@echo "$(GREEN)Next steps:$(NC)"
	@echo "  1. Run: make dev-init"
	@echo "  2. Run: make dev"

prod-setup: ## Setup for production (secure, Rails prod mode)
	@echo "$(BLUE)Setting up PRODUCTION environment...$(NC)"
	@if [ -f .env ]; then \
		echo "$(RED)✗ .env file already exists!$(NC)"; \
		echo ""; \
		echo "$(YELLOW)To avoid overwriting your configuration, please:$(NC)"; \
		echo "  1. Rename existing file:  mv .env .env.backup"; \
		echo "  2. Or remove it:          rm .env"; \
		echo "  3. Then run:              make prod-setup"; \
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
	LOOMIO_ADMIN_PASSWORD=$$(openssl rand -base64 24); \
	sed -i.bak "s/POSTGRES_PASSWORD=CHANGE_THIS_SECURE_PASSWORD/POSTGRES_PASSWORD=$$POSTGRES_PASSWORD/" .env; \
	sed -i.bak "s/SECRET_KEY_BASE=GENERATE_WITH_OPENSSL_RAND_HEX_64/SECRET_KEY_BASE=$$SECRET_KEY_BASE/" .env; \
	sed -i.bak "s/LOOMIO_HMAC_KEY=GENERATE_WITH_OPENSSL_RAND_HEX_32/LOOMIO_HMAC_KEY=$$LOOMIO_HMAC_KEY/" .env; \
	sed -i.bak "s/DEVISE_SECRET=GENERATE_WITH_OPENSSL_RAND_HEX_32/DEVISE_SECRET=$$DEVISE_SECRET/" .env; \
	sed -i.bak "s/BACKUP_ENCRYPTION_KEY=GENERATE_WITH_OPENSSL_RAND_HEX_32/BACKUP_ENCRYPTION_KEY=$$BACKUP_ENCRYPTION_KEY/" .env; \
	sed -i.bak "s/LOOMIO_ADMIN_PASSWORD=CHANGE_THIS_SECURE_PASSWORD/LOOMIO_ADMIN_PASSWORD=$$LOOMIO_ADMIN_PASSWORD/" .env; \
	rm .env.bak; \
	echo "$(GREEN)✓ Secrets generated!$(NC)"; \
	echo ""; \
	echo "$(GREEN)✓ Admin password generated:$(NC)"; \
	echo "  Password: $$LOOMIO_ADMIN_PASSWORD"
	@echo ""
	@echo "$(YELLOW)⚠ IMPORTANT: Edit .env and configure:$(NC)"
	@echo "  - CANONICAL_HOST (your domain)"
	@echo "  - LOOMIO_ADMIN_EMAIL (admin email)"
	@echo "  - SUPPORT_EMAIL"
	@echo "  - SMTP settings (email server)"
	@echo ""
	@echo "$(BLUE)Edit with: nano .env$(NC)"
	@echo ""
	@echo "$(GREEN)After editing, run: make prod-init$(NC)"

##@ Development Commands

dev: ## Start all services in development mode
	@if [ ! -f .env ]; then \
		echo "$(RED)✗ .env not found!$(NC)"; \
		echo "$(YELLOW)Run: make dev-setup$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Starting Loomio in DEVELOPMENT mode...$(NC)"
	@docker compose up -d
	@echo "$(GREEN)✓ Development stack started!$(NC)"
	@echo ""
	@echo "$(BLUE)Access Loomio at:$(NC)"
	@echo "  Web Interface:  http://localhost:3000"
	@echo "  Adminer:        http://localhost:8081"
	@echo ""
	@echo "$(YELLOW)View logs: make dev-logs$(NC)"

dev-init: ## Initialize database for development
	@if [ ! -f .env ]; then \
		echo "$(RED)✗ .env not found!$(NC)"; \
		echo "$(YELLOW)Run: make dev-setup$(NC)"; \
		exit 1; \
	fi
	@echo "$(BLUE)Initializing DEVELOPMENT database...$(NC)"
	@mkdir -p backups
	@docker compose pull
	@docker compose up -d db redis
	@echo "Waiting for database..."
	@sleep 10
	@docker compose run --rm app rake db:setup
	@echo "$(GREEN)✓ Development database initialized!$(NC)"
	@echo "$(GREEN)Ready! Run: make dev$(NC)"

dev-logs: ## Show development logs
	@docker compose logs -f

dev-status: ## Show development stack status
	@echo "$(BLUE)Development Stack Status:$(NC)"
	@docker compose ps

dev-stop: ## Stop development stack
	@echo "$(BLUE)Stopping development stack...$(NC)"
	@docker compose stop
	@echo "$(GREEN)✓ Stopped$(NC)"

dev-restart: ## Restart development stack
	@echo "$(BLUE)Restarting development stack...$(NC)"
	@docker compose restart
	@echo "$(GREEN)✓ Restarted$(NC)"

##@ Production Commands

prod-preflight: ## Validate production configuration before starting
	@echo "$(BLUE)Running production preflight checks...$(NC)"
	@if [ ! -f .env ]; then \
		echo "$(RED)✗ .env not found!$(NC)"; \
		exit 1; \
	fi
	@set -a; . .env; set +a; \
	ERRORS=0; \
	\
	echo "$(BLUE)Checking critical configuration...$(NC)"; \
	\
	if [ "$$RAILS_ENV" != "production" ]; then \
		echo "$(RED)✗ RAILS_ENV must be 'production' (currently: $$RAILS_ENV)$(NC)"; \
		ERRORS=$$((ERRORS + 1)); \
	else \
		echo "$(GREEN)✓ RAILS_ENV set to production$(NC)"; \
	fi; \
	\
	if [ -z "$$CANONICAL_HOST" ] || echo "$$CANONICAL_HOST" | grep -qE '(localhost|example\.com|127\.0\.0\.1)'; then \
		echo "$(RED)✗ CANONICAL_HOST must be set to your actual domain (not localhost/example.com)$(NC)"; \
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
	if [ -z "$$LOOMIO_ADMIN_PASSWORD" ] || echo "$$LOOMIO_ADMIN_PASSWORD" | grep -qE '(CHANGE|admin123|password)'; then \
		echo "$(YELLOW)⚠ WARNING: Admin password is weak or not set$(NC)"; \
	else \
		echo "$(GREEN)✓ Admin password configured$(NC)"; \
	fi; \
	\
	if [ "$$GDRIVE_ENABLED" != "true" ]; then \
		echo "$(RED)✗ GDRIVE_ENABLED must be 'true' for production (file backups)$(NC)"; \
		ERRORS=$$((ERRORS + 1)); \
	else \
		echo "$(GREEN)✓ Google Drive sync enabled$(NC)"; \
	fi; \
	\
	if [ -z "$$GDRIVE_CREDENTIALS" ] || echo "$$GDRIVE_CREDENTIALS" | grep -qE '(CHANGE|example)'; then \
		echo "$(RED)✗ GDRIVE_CREDENTIALS must be configured (service account JSON)$(NC)"; \
		ERRORS=$$((ERRORS + 1)); \
	else \
		echo "$(GREEN)✓ Google Drive credentials configured$(NC)"; \
	fi; \
	\
	if [ -z "$$GDRIVE_FOLDER_ID" ]; then \
		echo "$(RED)✗ GDRIVE_FOLDER_ID must be set (Google Drive folder for backups)$(NC)"; \
		ERRORS=$$((ERRORS + 1)); \
	else \
		echo "$(GREEN)✓ Google Drive folder ID configured$(NC)"; \
	fi; \
	\
	echo ""; \
	if [ $$ERRORS -gt 0 ]; then \
		echo "$(RED)✗ Production preflight failed with $$ERRORS critical error(s)$(NC)"; \
		echo "$(YELLOW)Fix the errors above before starting production$(NC)"; \
		exit 1; \
	else \
		echo "$(GREEN)✓ All critical checks passed$(NC)"; \
	fi

prod: prod-preflight ## Start all services in production mode
	@echo "$(BLUE)Starting Loomio in PRODUCTION mode...$(NC)"
	@docker compose up -d
	@echo "$(GREEN)✓ Production stack started!$(NC)"
	@echo ""
	@echo "$(BLUE)Access Loomio at:$(NC)"
	@set -a; . .env; set +a; \
	echo "  Web Interface:  https://$$CANONICAL_HOST"
	@echo "  Netdata:        http://$(shell hostname -I | awk '{print $$1}'):19999"
	@echo ""
	@echo "$(YELLOW)View logs: make prod-logs$(NC)"

prod-init: prod-preflight ## Initialize database for production
	@echo "$(BLUE)Initializing PRODUCTION database...$(NC)"
	@mkdir -p backups
	@docker compose build backup
	@docker compose pull
	@docker compose up -d db redis
	@echo "Waiting for database..."
	@sleep 30
	@docker compose run --rm app rake db:setup
	@echo "$(GREEN)✓ Production database initialized!$(NC)"
	@echo "$(GREEN)Ready! Run: make prod$(NC)"

prod-logs: ## Show production logs
	@docker compose logs -f

prod-status: ## Show production stack status
	@echo "$(BLUE)Production Stack Status:$(NC)"
	@docker compose ps

prod-stop: ## Stop production stack
	@echo "$(BLUE)Stopping production stack...$(NC)"
	@docker compose stop
	@echo "$(GREEN)✓ Stopped$(NC)"

prod-restart: ## Restart production stack
	@echo "$(BLUE)Restarting production stack...$(NC)"
	@docker compose restart
	@echo "$(GREEN)✓ Restarted$(NC)"

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
	@echo "  3. Admin user will be auto-created from .env credentials"

##@ Service Management

start: check-env ## Start all services
	@echo "$(BLUE)Starting Loomio stack...$(NC)"
	@docker compose up -d
	@echo "$(GREEN)✓ Loomio stack started!$(NC)"
	@echo ""
	@echo "$(BLUE)Access Loomio at:$(NC)"
	@echo "  Web Interface:  http://$(shell hostname -I | awk '{print $$1}'):3000"
	@echo "  Netdata:        http://$(shell hostname -I | awk '{print $$1}'):19999"
	@echo "  Adminer:        http://$(shell hostname -I | awk '{print $$1}'):8081"
	@echo ""
	@echo "$(YELLOW)View logs: make logs$(NC)"

stop: ## Stop all services
	@echo "$(BLUE)Stopping Loomio stack...$(NC)"
	@docker compose stop
	@echo "$(GREEN)✓ Services stopped$(NC)"

restart: ## Restart all services
	@echo "$(BLUE)Restarting Loomio stack...$(NC)"
	@docker compose restart
	@echo "$(GREEN)✓ Services restarted$(NC)"

down: ## Stop and remove all containers
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

##@ Backup & Restore

init-gdrive: check-env ## Initialize and validate Google Drive setup
	@echo "$(BLUE)Initializing Google Drive...$(NC)"
	@docker compose exec app bash /scripts/init-gdrive.sh

backup: check-env ## Create backup now (database + files)
	@echo "$(BLUE)Creating backup...$(NC)"
	@mkdir -p backups
	@docker compose exec backup python3 /app/backup.py
	@echo "$(GREEN)✓ Database backup complete!$(NC)"
	@echo ""
	@echo "$(BLUE)Syncing files to Google Drive...$(NC)"
	@$(MAKE) sync-files
	@echo ""
	@$(MAKE) list-backups

sync-files: check-env ## Sync file uploads to Google Drive
	@echo "$(BLUE)Syncing file uploads to Google Drive...$(NC)"
	@docker compose exec backup python3 /app/sync-files-to-gdrive.py || echo "$(YELLOW)⚠ File sync skipped or failed$(NC)"

restore-files: check-env ## Restore file uploads from Google Drive
	@echo "$(BLUE)Restoring file uploads from Google Drive...$(NC)"
	@docker compose exec app bash /scripts/restore-files-from-gdrive.sh

list-backups: ## List all backups
	@echo "$(BLUE)Available backups:$(NC)"
	@ls -lh backups/ 2>/dev/null || echo "No backups found"

restore: ## Restore database from backup
	@echo "$(YELLOW)⚠ This will restore your database from a backup$(NC)"
	@./scripts/restore-db.sh

##@ User Management

auto-create-admin: check-env ## Auto-create admin from .env variables
	@set -a; . .env; set +a; \
	if [ -n "$$LOOMIO_ADMIN_EMAIL" ] && [ -n "$$LOOMIO_ADMIN_PASSWORD" ]; then \
		echo "$(BLUE)Creating admin user from .env variables...$(NC)"; \
		ADMIN_NAME="$${LOOMIO_ADMIN_NAME:-Admin User}"; \
		docker compose run --rm app rails runner " \
			begin \
				existing_user = User.find_by(email: '$$LOOMIO_ADMIN_EMAIL'); \
				if existing_user \
					puts '✓ Admin user already exists: $$LOOMIO_ADMIN_EMAIL'; \
					if !existing_user.is_admin \
						existing_user.update(is_admin: true); \
						puts '✓ Promoted existing user to admin'; \
					end \
				else \
					user = User.create!( \
						email: '$$LOOMIO_ADMIN_EMAIL', \
						name: '$$ADMIN_NAME', \
						password: '$$LOOMIO_ADMIN_PASSWORD', \
						password_confirmation: '$$LOOMIO_ADMIN_PASSWORD', \
						email_verified: true, \
						is_admin: true \
					); \
					puts '✓ Created admin user: ' + user.email; \
				end \
			rescue StandardError => e \
				puts '✗ Failed to create admin user: ' + e.message; \
				exit 1; \
			end \
		" && echo "$(GREEN)✓ Admin user setup complete$(NC)" || echo "$(RED)✗ Admin user setup failed$(NC)"; \
	else \
		echo "$(YELLOW)No admin credentials in .env (LOOMIO_ADMIN_EMAIL/LOOMIO_ADMIN_PASSWORD)$(NC)"; \
		echo "Create admin with: make create-admin"; \
	fi

create-admin: check-env ## Create admin user with auto-generated password
	@echo "$(BLUE)═══════════════════════════════════════$(NC)"
	@echo "$(BLUE)       Create Loomio Admin User        $(NC)"
	@echo "$(BLUE)═══════════════════════════════════════$(NC)"
	@echo ""
	@read -p "Email address: " email; \
	read -p "Display name: " username; \
	if [ -z "$$email" ] || [ -z "$$username" ]; then \
		echo "$(RED)✗ Email and name are required!$(NC)"; \
		exit 1; \
	fi; \
	PASSWORD=$$(openssl rand -base64 12 | tr -d '/+=' | head -c 16); \
	echo ""; \
	echo "$(BLUE)Creating admin user...$(NC)"; \
	docker compose run --rm app rails runner " \
		begin \
			user = User.create!( \
				email: '$$email', \
				name: '$$username', \
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
		echo "$(YELLOW)Credentials:$(NC)"; \
		echo "  Email:    $$email"; \
		echo "  Name:     $$username"; \
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

promote-user: check-env ## Promote user to admin by email
	@read -p "Email address to promote: " email; \
	docker compose run --rm app rails runner " \
		user = User.find_by(email: '$$email'); \
		if user \
			user.update(is_admin: true); \
			puts 'User promoted to admin: ' + user.email; \
		else \
			puts 'User not found: $$email'; \
			exit 1; \
		end \
	" && echo "$(GREEN)✓ User promoted to admin$(NC)" || echo "$(RED)✗ User not found$(NC)"

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
	@docker compose exec db psql -U loomio -d loomio_production

##@ Maintenance

update: ## Update all containers
	@echo "$(BLUE)Updating all containers...$(NC)"
	@docker compose pull
	@docker compose up -d
	@echo "$(GREEN)✓ Update complete$(NC)"

clean: ## Clean up Docker resources
	@echo "$(BLUE)Cleaning up Docker resources...$(NC)"
	@docker system prune -f
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

health: ## Check health of all services
	@echo "$(BLUE)Running health checks...$(NC)"
	@./scripts/watchdog/health-monitor.sh

##@ Systemd Integration

enable-autostart: ## Enable automatic startup on boot
	@echo "$(BLUE)Enabling autostart...$(NC)"
	@if grep -q "RAILS_ENV=production" .env 2>/dev/null; then \
		echo "$(YELLOW)⚠ Production environment detected - running preflight checks...$(NC)"; \
		$(MAKE) prod-preflight || exit 1; \
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
	@echo "$(BLUE)Service URLs:$(NC)"
	@echo "  Loomio:         http://$(shell hostname -I | awk '{print $$1}'):3000"
	@echo "  Netdata:        http://$(shell hostname -I | awk '{print $$1}'):19999"
	@echo "  Adminer:        http://$(shell hostname -I | awk '{print $$1}'):8081"
	@echo ""
	@echo "$(BLUE)Container Versions:$(NC)"
	@docker compose images

##@ Quick Start

first-time-setup: ## Complete first-time setup (all steps)
	@echo "$(BLUE)╔════════════════════════════════════════════════╗$(NC)"
	@echo "$(BLUE)║   Loomio Pi Stack - First Time Setup          ║$(NC)"
	@echo "$(BLUE)╚════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(BLUE)Step 1/6: Installing dependencies...$(NC)"
	@$(MAKE) install
	@echo ""
	@echo "$(BLUE)Step 2/6: Creating .env and generating secrets...$(NC)"
	@$(MAKE) setup
	@echo ""
	@echo "$(YELLOW)╔════════════════════════════════════════════════╗$(NC)"
	@echo "$(YELLOW)║   IMPORTANT: Configure your .env file         ║$(NC)"
	@echo "$(YELLOW)╚════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(YELLOW)Required configuration:$(NC)"
	@echo "  • CANONICAL_HOST - Your domain (e.g., loomio.example.com)"
	@echo "  • SUPPORT_EMAIL - Support email address"
	@echo "  • SMTP_SERVER, SMTP_USERNAME, SMTP_PASSWORD - Email settings"
	@echo ""
	@echo "$(YELLOW)Optional (for auto admin creation):$(NC)"
	@echo "  • LOOMIO_ADMIN_EMAIL - Admin email"
	@echo "  • LOOMIO_ADMIN_PASSWORD - Admin password"
	@echo "  • LOOMIO_ADMIN_NAME - Admin name"
	@echo ""
	@echo "$(BLUE)Edit with: nano .env$(NC)"
	@echo ""
	@read -p "Press Enter when you're done editing .env..." dummy; \
	echo ""
	@echo "$(BLUE)Step 3/6: Initializing database...$(NC)"
	@$(MAKE) init
	@echo ""
	@echo "$(BLUE)Step 4/6: Starting all services...$(NC)"
	@$(MAKE) start
	@echo ""
	@echo "$(BLUE)Step 5/6: Enabling auto-start on boot...$(NC)"
	@$(MAKE) enable-autostart || echo "$(YELLOW)⚠ Skipped autostart (requires sudo)$(NC)"
	@echo ""
	@echo "$(BLUE)Step 6/6: Creating admin user...$(NC)"
	@$(MAKE) auto-create-admin
	@echo ""
	@echo "$(GREEN)╔════════════════════════════════════════════════╗$(NC)"
	@echo "$(GREEN)║   Loomio Pi Stack Setup Complete! 🎉          ║$(NC)"
	@echo "$(GREEN)╚════════════════════════════════════════════════╝$(NC)"
	@echo ""
	@echo "$(BLUE)Access Loomio:$(NC)"
	@echo "  Web Interface: http://$(shell hostname -I | awk '{print $$1}'):3000"
	@echo "  Netdata:       http://$(shell hostname -I | awk '{print $$1}'):19999"
	@echo "  Adminer:       http://$(shell hostname -I | awk '{print $$1}'):8081"
	@echo ""
	@set -a; . .env 2>/dev/null; set +a; \
	if [ -n "$$LOOMIO_ADMIN_EMAIL" ]; then \
		echo "$(GREEN)✓ Admin user: $$LOOMIO_ADMIN_EMAIL$(NC)"; \
	else \
		echo "$(YELLOW)Next steps to create admin:$(NC)"; \
		echo "  1. Open the web interface"; \
		echo "  2. Sign up for an account"; \
		echo "  3. Run: make promote-user"; \
	fi
	@echo ""
	@echo "$(YELLOW)Useful commands:$(NC)"
	@echo "  make logs          - View logs"
	@echo "  make status        - Check service status"
	@echo "  make backup        - Create backup"
	@echo "  make list-users    - List all users"
	@echo "  make help          - Show all commands"
