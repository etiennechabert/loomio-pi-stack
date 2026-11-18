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
export IS_RAM_MODE=${IS_RAM_MODE:-false}

echo "Configuration:"
echo "  Environment: ${RAILS_ENV}"
echo "  Storage: $([ "$IS_RAM_MODE" = "true" ] && echo "RAM (tmpfs)" || echo "Disk (volumes)")"
echo "  Database: ${DB_USER}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "  Backup Schedule:"
echo "    - Hourly:  Hours 1-23 (24h retention, permanent delete)"
echo "    - Daily:   Midnight Sun,Tue-Sat (7d retention, 30d in GDrive trash)"
echo "    - Weekly:  Midnight Monday (12wk retention, 30d in GDrive trash)"
echo "    - Manual:  On-demand (30d retention, 30d in GDrive trash)"
echo "  Google Drive: ${GDRIVE_ENABLED}"
echo ""

# Auto-restore on boot
echo "Checking if restore is needed..."

# The container healthcheck (which the app waits for) tests for RESTORE_MARKER.
# /tmp survives a restart of this container, so remove the marker left by a
# previous run: it must only exist once THIS run has finished its restore step.
RESTORE_MARKER="/tmp/.restore-complete"
# Present from the moment a restore starts writing to the database until it has
# been verified, so a half-finished restore is never mistaken for a populated
# database. Kept on the /backups bind mount rather than in /tmp, so it also
# survives Compose recreating this container while the database keeps running.
RESTORE_IN_PROGRESS="/backups/.restore-in-progress"
# Decrypted dump used during the restore (never leave one behind in /backups)
DECRYPTED="/backups/restore_boot.sql"
rm -f "$RESTORE_MARKER" "$DECRYPTED"

# How long to wait for PostgreSQL before giving up (seconds)
DB_WAIT_TIMEOUT=${DB_WAIT_TIMEOUT:-120}

# Run psql against the Loomio database; extra arguments are passed through
db_psql() {
    # -X: ignore any psqlrc, so output and session settings are predictable
    PGPASSWORD="${DB_PASSWORD}" PGCONNECT_TIMEOUT=10 \
        psql -X -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" "$@"
}

# Wait until PostgreSQL accepts connections and answers a query.
# Compose `depends_on` only orders `docker compose up`. When Docker restarts all
# containers at once (daemon restart, power loss) the database can still be
# initialising when this script starts, so a fixed sleep is not enough.
wait_for_db() {
    local deadline=$((SECONDS + DB_WAIT_TIMEOUT))
    local last_error=""

    echo "Waiting for database at ${DB_HOST}:${DB_PORT} (timeout: ${DB_WAIT_TIMEOUT}s)..."
    while true; do
        if last_error=$(db_psql -t -A -c "SELECT 1;" 2>&1 > /dev/null); then
            echo "✓ Database is accepting connections"
            return 0
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
            echo "✗ ERROR: Database did not accept connections within ${DB_WAIT_TIMEOUT}s"
            echo "  Last error: ${last_error:-unknown}"
            return 1
        fi
        sleep 2
    done
}

# Print the number of tables in the public schema.
# Fails (non-zero, nothing printed) if the query fails or does not return a
# plain number, so that "could not tell" is never read as "0" or as "populated".
count_public_tables() {
    local count
    count=$(db_psql -t -A -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';") || return 1
    count=${count//[[:space:]]/}
    case "$count" in
        '' | *[!0-9]*) return 1 ;;
    esac
    echo "$count"
}

if ! wait_for_db; then
    echo "✗ Cannot check or restore the database - exiting without marking the restore as complete"
    exit 1
fi

# In RAM mode, ALWAYS restore because tmpfs is wiped on boot
# In disk mode, only restore if database is empty
SHOULD_RESTORE=false

if [ "$IS_RAM_MODE" = "true" ]; then
    echo "${RAILS_ENV} mode (RAM): Always restoring from backup..."
    SHOULD_RESTORE=true
else
    # IS_RAM_MODE not set for this container (the case with the stock
    # docker-compose.yml): restore only if the database is empty
    if ! TABLE_COUNT=$(count_public_tables); then
        echo "✗ ERROR: Could not determine whether the database is empty (query failed or returned no number)"
        echo "  Not treating the database as populated - exiting without marking the restore as complete"
        exit 1
    fi

    if [ "$TABLE_COUNT" -eq 0 ]; then
        echo "Database is empty - attempting restore..."
        SHOULD_RESTORE=true
        # Nothing is left of any earlier, unfinished restore
        rm -f "$RESTORE_IN_PROGRESS"
    elif [ -f "$RESTORE_IN_PROGRESS" ]; then
        echo "✗ ERROR: An earlier restore did not finish, and the database is not empty (${TABLE_COUNT} tables)"
        echo "  The database may be only partly restored - not treating it as populated"
        echo "  To retry from a clean state see docs/RAM_MODE.md (\"Database restoration fails on startup\")"
        exit 1
    else
        echo "Database already populated (${TABLE_COUNT} tables) - skipping restore"
    fi
fi

if [ "$SHOULD_RESTORE" = "true" ]; then
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
        echo "Restoring from: $(basename "${LATEST_BACKUP}")"

        # Decrypt. The key is read from the environment (as backup.py does when
        # encrypting) so it never appears on a command line, and the plaintext
        # dump is created readable by its owner only.
        if ! python3 - "$LATEST_BACKUP" "$DECRYPTED" << 'PYEOF'
import base64, hashlib, os, sys
from cryptography.fernet import Fernet

def derive_fernet_key(password):
    return base64.urlsafe_b64encode(hashlib.pbkdf2_hmac('sha256', password.encode(), b'loomio-backup-salt', 100000, dklen=32))

source, target = sys.argv[1], sys.argv[2]
fernet = Fernet(derive_fernet_key(os.environ.get('BACKUP_ENCRYPTION_KEY', '')))
with open(source, 'rb') as f:
    data = fernet.decrypt(f.read())
with os.fdopen(os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), 'wb') as out:
    out.write(data)
PYEOF
        then
            rm -f "$DECRYPTED"
            echo "✗ Restore failed: could not decrypt $(basename "${LATEST_BACKUP}") (wrong BACKUP_ENCRYPTION_KEY or damaged file)"
            echo "  Exiting without marking the restore as complete"
            exit 1
        fi

        # Restore
        # psql exits 0 even when individual statements fail, so a zero exit code
        # is not enough: also check that the database has tables afterwards.
        touch "$RESTORE_IN_PROGRESS"
        RESTORE_ERROR=""
        if ! db_psql < "$DECRYPTED" > /dev/null 2>&1; then
            RESTORE_ERROR="psql reported an error (database unreachable, or connection lost during the restore)"
        elif ! RESTORED_TABLES=$(count_public_tables); then
            RESTORE_ERROR="could not check the database after the restore"
        elif [ "$RESTORED_TABLES" -eq 0 ]; then
            RESTORE_ERROR="the database still has no tables after the restore"
        fi
        rm -f "$DECRYPTED"

        if [ -n "$RESTORE_ERROR" ]; then
            echo "✗ Restore failed: ${RESTORE_ERROR}"
            echo "  Exiting without marking the restore as complete, so this container is not reported healthy"
            exit 1
        fi

        rm -f "$RESTORE_IN_PROGRESS"
        echo "✓ Database restored successfully! (${RESTORED_TABLES} tables)"
    else
        echo "No backup available - database will remain empty"
    fi
fi

# Auto-restore uploads on boot
echo ""
echo "Checking if uploads restore is needed..."

# In RAM mode, always sync uploads to ensure latest files
# In disk mode, only sync if directories are empty
SHOULD_SYNC_UPLOADS=false

if [ "$IS_RAM_MODE" = "true" ] && [ "${GDRIVE_ENABLED}" = "true" ] && [ -n "${GDRIVE_TOKEN}" ] && [ -n "${GDRIVE_FOLDER_ID}" ]; then
    echo "${RAILS_ENV} mode (RAM): Always syncing uploads..."
    SHOULD_SYNC_UPLOADS=true
else
    # Development: check if uploads are empty
    UPLOAD_COUNT=$(find /loomio/storage /loomio/public/system /loomio/public/files -type f 2>/dev/null | wc -l | tr -d ' ')
    if [ "$UPLOAD_COUNT" -eq "0" ] && [ "${GDRIVE_ENABLED}" = "true" ] && [ -n "${GDRIVE_TOKEN}" ] && [ -n "${GDRIVE_FOLDER_ID}" ]; then
        echo "Upload directories are empty - downloading from Google Drive..."
        SHOULD_SYNC_UPLOADS=true
    else
        if [ "$UPLOAD_COUNT" -gt "0" ]; then
            echo "Uploads already present (${UPLOAD_COUNT} files) - skipping restore"
        else
            echo "Google Drive not configured - skipping uploads restore"
        fi
    fi
fi

if [ "$SHOULD_SYNC_UPLOADS" = "true" ]; then
    # Create rclone config
    RCLONE_CONFIG_DIR="/tmp/rclone-config-uploads-$$"
    mkdir -p "$RCLONE_CONFIG_DIR"
    cat > "$RCLONE_CONFIG_DIR/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
token = ${GDRIVE_TOKEN}
root_folder_id = ${GDRIVE_FOLDER_ID}
EOF

    # Sync uploads from Google Drive
    echo "Syncing uploads from Google Drive..."
    for upload_dir in storage system files; do
        if [ "$upload_dir" = "storage" ]; then
            TARGET="/loomio/storage"
        elif [ "$upload_dir" = "system" ]; then
            TARGET="/loomio/public/system"
        else
            TARGET="/loomio/public/files"
        fi

        echo "  → Syncing $upload_dir to $TARGET..."
        rclone sync "gdrive:${RAILS_ENV}/uploads/$upload_dir" "$TARGET" \
            --config "$RCLONE_CONFIG_DIR/rclone.conf" \
            --progress 2>&1 | grep -E "(Transferred|Elapsed|Checks)" || true
    done

    rm -rf "$RCLONE_CONFIG_DIR"
    echo "✓ Uploads synced from Google Drive"
fi

# Mark restore as complete (for healthcheck)
touch "$RESTORE_MARKER"
echo "✓ Restore process complete"

# Set up cron jobs for multi-tier backups
echo "Setting up backup schedules..."

# Create crontab with all backup schedules (using root crontab, not /etc/cron.d)
crontab - << EOF
# Loomio Multi-Tier Backup Schedule
# Logs are redirected to container stdout for visibility

# Set PATH and environment for cron jobs
PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASSWORD=${DB_PASSWORD}
BACKUP_ENCRYPTION_KEY=${BACKUP_ENCRYPTION_KEY}
GDRIVE_ENABLED=${GDRIVE_ENABLED}
GDRIVE_TOKEN=${GDRIVE_TOKEN}
GDRIVE_FOLDER_ID=${GDRIVE_FOLDER_ID}
RAILS_ENV=${RAILS_ENV}

# Hourly backups (24h retention) - Hours 1-23 (skips midnight for daily/weekly)
0 1-23 * * * /app/backup-hourly.sh >> /proc/1/fd/1 2>&1

# Daily backups at midnight (7d retention) - skips Monday for weekly
0 0 * * 0,2-6 /app/backup-daily.sh >> /proc/1/fd/1 2>&1

# Weekly backups at midnight on Monday (12wk retention)
0 0 * * 1 /app/backup-weekly.sh >> /proc/1/fd/1 2>&1

EOF

echo ""
echo "Backup service started successfully"
echo "Cron schedules active:"
echo "  - Hourly:  0 1-23 * * * (hours 1-23)"
echo "  - Daily:   0 0 * * 0,2-6 (midnight, Sun,Tue-Sat)"
echo "  - Weekly:  0 0 * * 1 (midnight, Monday)"
echo ""
echo "Logs will appear below:"
echo "================================="

# Start cron in foreground
cron -f
