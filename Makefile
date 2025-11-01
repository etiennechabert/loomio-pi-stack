.PHONY: help install setup start stop restart status logs clean backup restore update health check-config generate-secrets enable-autostart disable-autostart test

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

install: ## Install Docker and dependencies (first time setup)
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
	@sudo apt install -y git openssl python3 python3-pip make tree
	@echo "$(GREEN)✓ Installation complete!$(NC)"

check-env: ## Check if .env file exists
	@if [ ! -f .env ]; then \
		echo "$(RED)✗ .env file not found!$(NC)"; \
		echo "$(YELLOW)Run: make setup$(NC)"; \
		exit 1; \
	fi

setup: ## Initial setup - create .env and generate secrets
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
	sed -i.bak "s/SECRET_KEY_BASE=generate-with-openssl-rand-hex-64/SECRET_KEY_BASE=$$SECRET_KEY_BASE/" .env; \
	sed -i.bak "s/LOOMIO_HMAC_KEY=generate-with-openssl-rand-hex-32/LOOMIO_HMAC_KEY=$$LOOMIO_HMAC_KEY/" .env; \
	sed -i.bak "s/DEVISE_SECRET=generate-with-openssl-rand-hex-32/DEVISE_SECRET=$$DEVISE_SECRET/" .env; \
	sed -i.bak "s/BACKUP_ENCRYPTION_KEY=generate-with-openssl-rand-hex-32/BACKUP_ENCRYPTION_KEY=$$BACKUP_ENCRYPTION_KEY/" .env; \
	sed -i.bak "s/POSTGRES_PASSWORD=change-this-secure-password/POSTGRES_PASSWORD=$$POSTGRES_PASSWORD/" .env; \
	rm .env.bak
	@echo "$(GREEN)✓ Secrets generated!$(NC)"
	@echo ""
	@echo "$(YELLOW)⚠ IMPORTANT: Edit .env and configure:$(NC)"
	@echo "  - CANONICAL_HOST (your domain)"
	@echo "  - SUPPORT_EMAIL"
	@echo "  - SMTP settings (email server)"
	@echo ""
	@echo "$(BLUE)Edit with: nano .env$(NC)"
	@echo ""
	@echo "$(GREEN)After editing .env, run: make init$(NC)"

generate-secrets: ## Generate new secrets (dangerous - will break existing installation!)
	@echo "$(RED)⚠ WARNING: This will generate new secrets!$(NC)"
	@echo "$(RED)This will break your existing Loomio installation!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		echo "Generating new secrets..."; \
		echo "SECRET_KEY_BASE=$$(openssl rand -hex 64)"; \
		echo "LOOMIO_HMAC_KEY=$$(openssl rand -hex 32)"; \
		echo "DEVISE_SECRET=$$(openssl rand -hex 32)"; \
		echo "BACKUP_ENCRYPTION_KEY=$$(openssl rand -hex 32)"; \
		echo "POSTGRES_PASSWORD=$$(openssl rand -base64 32)"; \
		echo ""; \
		echo "$(YELLOW)Copy these values to your .env file$(NC)"; \
	else \
		echo "Cancelled."; \
	fi

check-config: ## Validate configuration files
	@echo "$(BLUE)Validating configuration...$(NC)"
	@echo "Checking docker-compose.yml..."
	@docker compose config > /dev/null && echo "$(GREEN)✓ docker-compose.yml is valid$(NC)" || echo "$(RED)✗ docker-compose.yml has errors$(NC)"
	@echo "Checking .env file..."
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
	@echo "Checking required scripts..."
	@for script in scripts/*.sh scripts/watchdog/*.sh; do \
		if [ -x "$$script" ]; then \
			echo "$(GREEN)✓ $$script is executable$(NC)"; \
		else \
			echo "$(RED)✗ $$script is not executable$(NC)"; \
			chmod +x "$$script"; \
		fi; \
	done

##@ Service Management

init: check-env ## Initialize database (first time only)
	@echo "$(BLUE)Building services...$(NC)"
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

auto-create-admin: check-env ## Auto-create admin user from environment variables
	@if [ -n "$$LOOMIO_ADMIN_EMAIL" ] && [ -n "$$LOOMIO_ADMIN_PASSWORD" ]; then \
		echo "$(BLUE)Creating admin user from environment variables...$(NC)"; \
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
	@echo "$(YELLOW)View logs with: make logs$(NC)"

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

ps: status ## Alias for status

logs: ## Show logs from all services (follow mode)
	@docker compose logs -f

logs-app: ## Show logs from app only
	@docker compose logs -f app

logs-backup: ## Show logs from backup service
	@docker compose logs -f backup

logs-db: ## Show logs from database
	@docker compose logs -f db

##@ Backup & Restore

backup: check-env ## Create manual backup now
	@echo "$(BLUE)Creating backup...$(NC)"
	@docker compose exec backup python3 /app/backup.py
	@echo "$(GREEN)✓ Backup complete!$(NC)"
	@echo ""
	@make list-backups

list-backups: ## List all backups
	@echo "$(BLUE)Available backups:$(NC)"
	@ls -lh backups/ 2>/dev/null || echo "No backups found"

restore: ## Restore database from backup (interactive)
	@echo "$(YELLOW)⚠ This will restore your database from a backup$(NC)"
	@./scripts/restore-db.sh

backup-now: backup ## Alias for backup

##@ Database Management

db-console: check-env ## Open PostgreSQL console
	@echo "$(BLUE)Opening database console...$(NC)"
	@docker compose exec db psql -U loomio -d loomio_production

db-shell: db-console ## Alias for db-console

rails-console: check-env ## Open Rails console
	@echo "$(BLUE)Opening Rails console...$(NC)"
	@docker compose run --rm app rails c

rails-c: rails-console ## Alias for rails-console

make-admin: check-env ## Make the last registered user an admin
	@echo "$(BLUE)Making last user an admin...$(NC)"
	@docker compose run --rm app rails runner "User.last.update(is_admin: true)"
	@echo "$(GREEN)✓ Last user is now admin$(NC)"

create-admin: check-env ## Create a new admin user (interactive)
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
	" && echo "$(GREEN)✓ Admin user created!$(NC)" || echo "$(RED)✗ Failed to create user (may already exist)$(NC)"

list-users: check-env ## List all users
	@echo "$(BLUE)Loomio Users:$(NC)"
	@docker compose run --rm app rails runner " \
		User.order(:created_at).each do |u| \
			admin_label = u.is_admin ? ' [ADMIN]' : ''; \
			verified = u.email_verified ? '✓' : '✗'; \
			puts \"#{verified} #{u.email} - #{u.name}#{admin_label}\"; \
		end \
	"

promote-user: check-env ## Make a specific user admin (by email)
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

db-backup-manual: ## Create database backup manually (without encryption)
	@echo "$(BLUE)Creating manual database backup...$(NC)"
	@mkdir -p backups
	@docker compose exec db pg_dump -U loomio -d loomio_production > backups/manual_backup_$(shell date +%Y%m%d_%H%M%S).sql
	@echo "$(GREEN)✓ Manual backup created$(NC)"

##@ Monitoring & Health

health: ## Check health of all services
	@echo "$(BLUE)Running health checks...$(NC)"
	@./scripts/watchdog/health-monitor.sh

stats: ## Show resource usage statistics
	@echo "$(BLUE)Container Resource Usage:$(NC)"
	@docker stats --no-stream

top: ## Show running processes in containers
	@docker compose top

netdata: ## Open Netdata dashboard in browser
	@echo "$(BLUE)Opening Netdata dashboard...$(NC)"
	@xdg-open http://localhost:19999 2>/dev/null || open http://localhost:19999 2>/dev/null || echo "Open http://localhost:19999 in your browser"

##@ Maintenance

update: ## Update all containers to latest versions
	@echo "$(BLUE)Updating all containers...$(NC)"
	@docker compose pull
	@docker compose up -d
	@echo "$(GREEN)✓ Update complete$(NC)"

clean: ## Clean up old Docker images and containers
	@echo "$(BLUE)Cleaning up Docker resources...$(NC)"
	@docker system prune -f
	@echo "$(GREEN)✓ Cleanup complete$(NC)"

clean-all: ## Clean up everything including volumes (DANGEROUS!)
	@echo "$(RED)⚠ WARNING: This will delete all data!$(NC)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose down -v; \
		echo "$(GREEN)✓ All data removed$(NC)"; \
	else \
		echo "Cancelled."; \
	fi

clean-backups: ## Remove backups older than 30 days
	@echo "$(BLUE)Cleaning old backups...$(NC)"
	@find backups/ -name "loomio_backup_*.sql*" -mtime +30 -delete 2>/dev/null || true
	@echo "$(GREEN)✓ Old backups removed$(NC)"

rebuild: ## Rebuild all containers from scratch
	@echo "$(BLUE)Rebuilding all containers...$(NC)"
	@docker compose build --no-cache
	@docker compose up -d
	@echo "$(GREEN)✓ Rebuild complete$(NC)"

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

systemd-status: ## Show systemd service status
	@echo "$(BLUE)Systemd Service Status:$(NC)"
	@sudo systemctl status loomio.service --no-pager || true
	@echo ""
	@sudo systemctl status loomio-watchdog.timer --no-pager || true

##@ Testing & Troubleshooting

test: ## Run basic functionality tests
	@echo "$(BLUE)Running tests...$(NC)"
	@echo "Checking Docker..."
	@docker --version
	@echo "Checking Docker Compose..."
	@docker compose version
	@echo "Validating configuration..."
	@docker compose config > /dev/null && echo "$(GREEN)✓ Configuration valid$(NC)"
	@echo "Checking services..."
	@docker compose ps
	@echo "Testing database connection..."
	@docker compose exec -T db pg_isready -U loomio && echo "$(GREEN)✓ Database ready$(NC)"
	@echo "Testing app health..."
	@curl -f http://localhost:3000/api/v1/ping 2>/dev/null && echo "$(GREEN)✓ App responding$(NC)" || echo "$(YELLOW)⚠ App not responding$(NC)"
	@echo ""
	@echo "$(GREEN)✓ Tests complete$(NC)"

troubleshoot: ## Run troubleshooting checks
	@echo "$(BLUE)Running troubleshooting checks...$(NC)"
	@echo ""
	@echo "$(BLUE)1. Checking Docker status...$(NC)"
	@sudo systemctl status docker --no-pager | head -n 3
	@echo ""
	@echo "$(BLUE)2. Checking disk space...$(NC)"
	@df -h / | tail -n 1
	@echo ""
	@echo "$(BLUE)3. Checking memory...$(NC)"
	@free -h | grep Mem
	@echo ""
	@echo "$(BLUE)4. Checking container status...$(NC)"
	@docker compose ps
	@echo ""
	@echo "$(BLUE)5. Checking for errors in logs...$(NC)"
	@docker compose logs --tail=50 | grep -i error || echo "No recent errors found"
	@echo ""
	@echo "$(BLUE)6. Checking network connectivity...$(NC)"
	@docker compose exec -T db pg_isready -U loomio && echo "$(GREEN)✓ Database accessible$(NC)" || echo "$(RED)✗ Database not accessible$(NC)"
	@echo ""
	@echo "For detailed logs, run: make logs"

reset-permissions: ## Fix file permissions
	@echo "$(BLUE)Fixing file permissions...$(NC)"
	@chmod +x scripts/*.sh
	@chmod +x scripts/watchdog/*.sh
	@chmod +x backup-service/*.sh
	@chmod +x backup-service/*.py
	@echo "$(GREEN)✓ Permissions fixed$(NC)"

##@ Information

info: ## Show system and stack information
	@echo "$(BLUE)Loomio Pi Stack Information$(NC)"
	@echo ""
	@echo "$(BLUE)System:$(NC)"
	@echo "  Hostname:       $(shell hostname)"
	@echo "  IP Address:     $(shell hostname -I | awk '{print $$1}')"
	@echo "  OS:             $(shell uname -s)"
	@echo "  Architecture:   $(shell uname -m)"
	@echo ""
	@echo "$(BLUE)Docker:$(NC)"
	@docker --version
	@docker compose version
	@echo ""
	@echo "$(BLUE)Services:$(NC)"
	@docker compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
	@echo ""
	@echo "$(BLUE)Disk Usage:$(NC)"
	@df -h / | tail -n 1
	@echo ""
	@echo "$(BLUE)Memory Usage:$(NC)"
	@free -h | grep Mem
	@echo ""
	@echo "$(BLUE)URLs:$(NC)"
	@echo "  Loomio:   http://$(shell hostname -I | awk '{print $$1}'):3000"
	@echo "  Netdata:  http://$(shell hostname -I | awk '{print $$1}'):19999"
	@echo "  Adminer:  http://$(shell hostname -I | awk '{print $$1}'):8081"

urls: ## Show service URLs
	@echo "$(BLUE)Service URLs:$(NC)"
	@echo "  Loomio Web:     http://$(shell hostname -I | awk '{print $$1}'):3000"
	@echo "  Channels:       http://$(shell hostname -I | awk '{print $$1}'):5000"
	@echo "  Hocuspocus:     http://$(shell hostname -I | awk '{print $$1}'):4000"
	@echo "  Netdata:        http://$(shell hostname -I | awk '{print $$1}'):19999"
	@echo "  Adminer:        http://$(shell hostname -I | awk '{print $$1}'):8081"

version: ## Show versions of all components
	@echo "$(BLUE)Component Versions:$(NC)"
	@docker compose images

##@ Quick Start Workflows

first-time-setup: install setup init start enable-autostart auto-create-admin ## Complete first-time setup (all steps)
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
	@if [ -n "$$LOOMIO_ADMIN_EMAIL" ]; then \
		echo "$(GREEN)✓ Admin user created: $$LOOMIO_ADMIN_EMAIL$(NC)"; \
	else \
		echo "$(YELLOW)Next steps:$(NC)"; \
		echo "  1. Open the web interface"; \
		echo "  2. Sign up for an account"; \
		echo "  3. Run: make make-admin"; \
		echo ""; \
		echo "$(BLUE)Or create admin directly:$(NC) make create-admin"; \
	fi
	@echo ""
	@echo "$(YELLOW)Useful commands:$(NC)"
	@echo "  make logs          - View logs"
	@echo "  make status        - Check service status"
	@echo "  make backup        - Create backup"
	@echo "  make list-users    - List all users"
	@echo "  make help          - Show all commands"

full-reset: stop clean-all setup init start ## Complete reset (deletes all data!)
	@echo "$(GREEN)✓ Full reset complete$(NC)"

emergency-restore: ## Emergency restore from latest backup
	@echo "$(RED)Emergency Restore Mode$(NC)"
	@./scripts/restore-db.sh
