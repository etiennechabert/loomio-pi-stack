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

# Auto-restore on boot if database is empty
echo "Checking if database restore is needed..."
sleep 5  # Wait for database to be fully ready

# Check if database is empty
TABLE_COUNT=$(PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")

if [ "$TABLE_COUNT" -eq "0" ]; then
    echo "Database is empty - attempting restore..."

    # Look for latest backup locally
    LATEST_BACKUP=$(ls -t /backups/*.sql.enc 2>/dev/null | head -1)

    # If no local backup and GDrive is configured, download latest
    if [ -z "${LATEST_BACKUP}" ] && [ "${GDRIVE_ENABLED}" = "true" ] && [ -n "${GDRIVE_TOKEN}" ] && [ -n "${GDRIVE_FOLDER_ID}" ]; then
        echo "No local backup - downloading from Google Drive..."

        # Create rclone config
        RCLONE_CONFIG_DIR="/tmp/rclone-config-$$"
        mkdir -p "$RCLONE_CONFIG_DIR"
        cat > "$RCLONE_CONFIG_DIR/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
token = ${GDRIVE_TOKEN}
root_folder_id = ${GDRIVE_FOLDER_ID}
EOF

        # Find and download latest backup
        LATEST_FILE=$(rclone lsf "gdrive:${RAILS_ENV}/backups"             --config "$RCLONE_CONFIG_DIR/rclone.conf"             --files-only             --include '*.sql.enc' | grep -v '.partial' | sort -r | head -1)

        if [ -n "$LATEST_FILE" ]; then
            echo "Downloading: $LATEST_FILE"
            rclone copy "gdrive:${RAILS_ENV}/backups/$LATEST_FILE" "/backups"                 --config "$RCLONE_CONFIG_DIR/rclone.conf"
        fi

        rm -rf "$RCLONE_CONFIG_DIR"
        LATEST_BACKUP=$(ls -t /backups/*.sql.enc 2>/dev/null | head -1)
    fi

    # Restore if we have a backup
    if [ -n "${LATEST_BACKUP}" ]; then
        echo "Restoring from: $(basename ${LATEST_BACKUP})"

        # Decrypt
        DECRYPTED="/backups/restore_boot.sql"
        python3 -c "
from cryptography.fernet import Fernet
import base64, hashlib

def derive_fernet_key(password):
    return base64.urlsafe_b64encode(hashlib.pbkdf2_hmac('sha256', password.encode(), b'loomio-backup-salt', 100000, dklen=32))

fernet = Fernet(derive_fernet_key('${BACKUP_ENCRYPTION_KEY}'))
with open('${LATEST_BACKUP}', 'rb') as f:
    with open('${DECRYPTED}', 'wb') as out:
        out.write(fernet.decrypt(f.read()))
"

        # Restore
        PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -U ${DB_USER} -d ${DB_NAME} < ${DECRYPTED} > /dev/null 2>&1 && echo "✓ Database restored successfully!" || echo "✗ Restore failed"
        rm -f ${DECRYPTED}
    else
        echo "No backup available - database will remain empty"
    fi
else
    echo "Database already populated (${TABLE_COUNT} tables) - skipping restore"
fi

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
