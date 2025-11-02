.PHONY: help install setup init start stop restart down status logs backup restore update clean enable-autostart disable-autostart check-config health first-time-setup

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
		echo "$(YELLOW)⚠ .env already exists. Backup created as .env.backup$(NC)"; \
		cp .env .env.backup; \
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
	rm .env.bak
	@echo "$(GREEN)✓ Secrets generated!$(NC)"
	@echo ""
	@echo "$(GREEN)✓ Admin credentials generated:$(NC)"
	@echo "  Email: admin@loomio.local"
	@. .env && echo "  Password: $$LOOMIO_ADMIN_PASSWORD"
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

backup: check-env ## Create backup now
	@echo "$(BLUE)Creating backup...$(NC)"
	@mkdir -p backups
	@docker compose exec backup python3 /app/backup.py
	@echo "$(GREEN)✓ Backup complete!$(NC)"
	@echo ""
	@$(MAKE) list-backups

list-backups: ## List all backups
	@echo "$(BLUE)Available backups:$(NC)"
	@ls -lh backups/ 2>/dev/null || echo "No backups found"

restore: ## Restore database from backup
	@echo "$(YELLOW)⚠ This will restore your database from a backup$(NC)"
	@./scripts/restore-db.sh

##@ User Management

auto-create-admin: check-env ## Auto-create admin from .env variables
	@set -a; source .env; set +a; \
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
			rescue => e \
				puts '✗ Failed to create admin user: ' + e.message; \
				exit 1; \
			end \
		" && echo "$(GREEN)✓ Admin user setup complete$(NC)" || echo "$(RED)✗ Admin user setup failed$(NC)"; \
	else \
		echo "$(YELLOW)No admin credentials in .env (LOOMIO_ADMIN_EMAIL/LOOMIO_ADMIN_PASSWORD)$(NC)"; \
		echo "Create admin with: make create-admin"; \
	fi

create-admin: check-env ## Create admin user (interactive)
	@echo "$(BLUE)Create Admin User$(NC)"
	@echo ""
	@read -p "Email address: " email; \
	read -p "Username: " username; \
	read -sp "Password: " password; \
	echo ""; \
	read -sp "Confirm password: " password2; \
	echo ""; \
	if [ "$$password" != "$$password2" ]; then \
		echo "$(RED)✗ Passwords don't match!$(NC)"; \
		exit 1; \
	fi; \
	if [ -z "$$email" ] || [ -z "$$username" ] || [ -z "$$password" ]; then \
		echo "$(RED)✗ All fields are required!$(NC)"; \
		exit 1; \
	fi; \
	echo "Creating admin user..."; \
	docker compose run --rm app rails runner " \
		user = User.create!( \
			email: '$$email', \
			name: '$$username', \
			password: '$$password', \
			password_confirmation: '$$password', \
			email_verified: true, \
			is_admin: true \
		); \
		puts 'Admin user created: ' + user.email \
	" && echo "$(GREEN)✓ Admin user created!$(NC)" || echo "$(RED)✗ Failed to create user$(NC)"

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
	@set -a; source .env 2>/dev/null; set +a; \
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
