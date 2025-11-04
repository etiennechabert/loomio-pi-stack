#!/bin/bash
set -e

echo "Loomio Backup Service - Starting"
echo "================================="

# Validate required environment variables
if [ -z "$DB_PASSWORD" ]; then
    echo "ERROR: DB_PASSWORD is not set"
    exit 1
fi

if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
    echo "WARNING: BACKUP_ENCRYPTION_KEY is not set - backups will not be encrypted!"
fi

# Set defaults
export DB_HOST=${DB_HOST:-db}
export DB_PORT=${DB_PORT:-5432}
export DB_NAME=${DB_NAME:-loomio_production}
export DB_USER=${DB_USER:-loomio}
export BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}
export GDRIVE_ENABLED=${GDRIVE_ENABLED:-false}
export RAILS_ENV=${RAILS_ENV:-development}

# Auto-adjust backup schedule based on environment
# Production = RAM mode = hourly backups
if [ "$RAILS_ENV" = "production" ]; then
    export BACKUP_SCHEDULE="0 * * * *"  # Hourly in production/RAM mode
    export IS_RAM_MODE="true"
    echo "Production Mode (RAM): using HOURLY backups"
else
    export BACKUP_SCHEDULE=${BACKUP_SCHEDULE:-"0 */6 * * *"}  # Every 6 hours in dev
    export IS_RAM_MODE="false"
    echo "Development Mode (Disk): using 6-hourly backups"
fi

echo "Configuration:"
echo "  Environment: ${RAILS_ENV}"
echo "  Storage: $([ "$IS_RAM_MODE" = "true" ] && echo "RAM (tmpfs)" || echo "Disk (volumes)")"
echo "  Database: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "  Schedule: ${BACKUP_SCHEDULE}"
echo "  Retention: ${BACKUP_RETENTION_DAYS} days"
echo "  Google Drive: ${GDRIVE_ENABLED}"
echo ""

# Skip initial backup - only backup via cron schedule
# This prevents creating empty database backups during initialization

# Set up cron job for scheduled backups and sync
echo "${BACKUP_SCHEDULE} /app/backup-and-sync.sh >> /proc/1/fd/1 2>&1" > /etc/cron.d/loomio-backup
chmod 0644 /etc/cron.d/loomio-backup
crontab /etc/cron.d/loomio-backup

echo ""
echo "Backup service started successfully"
echo "Cron schedule: ${BACKUP_SCHEDULE}"
echo "Logs will appear below:"
echo "================================="

# Start cron in foreground
cron -f
