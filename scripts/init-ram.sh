#!/bin/bash
#
# Initialize RAM-based Database
# Restores database from local backup (or Google Drive if missing)
#

set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Load environment
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    log "${RED}✗ .env file not found!${NC}"
    exit 1
fi

log "${BLUE}═══════════════════════════════════════════════════${NC}"
log "${BLUE}  RAM Database Initialization${NC}"
log "${BLUE}═══════════════════════════════════════════════════${NC}"

LOCAL_BACKUP_DIR="./data/db_backup"
mkdir -p "$LOCAL_BACKUP_DIR"

# Check for local backup first
LATEST_BACKUP=$(ls -t "$LOCAL_BACKUP_DIR"/loomio_backup_*.sql.enc 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    log "${YELLOW}⚠ No local backup found${NC}"

    # Try to download from Google Drive
    if [ "${GDRIVE_ENABLED}" = "true" ] && [ -n "${GDRIVE_CREDENTIALS}" ] && [ -n "${GDRIVE_FOLDER_ID}" ]; then
        log "${BLUE}Downloading latest backup from Google Drive...${NC}"

        RCLONE_CONFIG_DIR="/tmp/rclone-config-$$"
        mkdir -p "$RCLONE_CONFIG_DIR"

        cat > "$RCLONE_CONFIG_DIR/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
service_account_credentials = ${GDRIVE_CREDENTIALS}
root_folder_id = ${GDRIVE_FOLDER_ID}
EOF

        # Download latest backup
        rclone copy "gdrive:Backup/db_backup" "$LOCAL_BACKUP_DIR" \
            --config "$RCLONE_CONFIG_DIR/rclone.conf" \
            --max-age 7d \
            --progress

        rm -rf "$RCLONE_CONFIG_DIR"

        # Check again
        LATEST_BACKUP=$(ls -t "$LOCAL_BACKUP_DIR"/loomio_backup_*.sql.enc 2>/dev/null | head -1)

        if [ -z "$LATEST_BACKUP" ]; then
            log "${RED}✗ No backup found locally or in Google Drive${NC}"
            log "${YELLOW}Starting with fresh database...${NC}"
            log "${YELLOW}Run 'make init' to set up a new database${NC}"
            exit 0
        fi

        log "${GREEN}✓ Downloaded backup from Google Drive${NC}"
    else
        log "${YELLOW}⚠ Google Drive not configured${NC}"
        log "${YELLOW}Starting with fresh database...${NC}"
        log "${YELLOW}Run 'make init' to set up a new database${NC}"
        exit 0
    fi
else
    log "${GREEN}✓ Found local backup: $(basename $LATEST_BACKUP)${NC}"
fi

# Check backup age
BACKUP_AGE_SECONDS=$(($(date +%s) - $(stat -f %m "$LATEST_BACKUP" 2>/dev/null || stat -c %Y "$LATEST_BACKUP")))
BACKUP_AGE_HOURS=$((BACKUP_AGE_SECONDS / 3600))

if [ $BACKUP_AGE_HOURS -gt 24 ]; then
    log "${YELLOW}⚠ WARNING: Backup is ${BACKUP_AGE_HOURS} hours old${NC}"
    log "${YELLOW}Consider syncing from Google Drive if this seems wrong${NC}"
fi

# Decrypt backup
log "${BLUE}Decrypting backup...${NC}"
DECRYPTED_FILE="${LATEST_BACKUP%.enc}"

python3 -c "
from cryptography.fernet import Fernet
import base64
import hashlib
import sys

def derive_fernet_key(password):
    kdf_output = hashlib.pbkdf2_hmac('sha256', password.encode(), b'loomio-backup-salt', 100000, dklen=32)
    return base64.urlsafe_b64encode(kdf_output)

try:
    fernet_key = derive_fernet_key('${BACKUP_ENCRYPTION_KEY}')
    fernet = Fernet(fernet_key)

    with open('${LATEST_BACKUP}', 'rb') as f:
        encrypted_data = f.read()

    decrypted_data = fernet.decrypt(encrypted_data)

    with open('${DECRYPTED_FILE}', 'wb') as f:
        f.write(decrypted_data)

    print('✓ Decrypted successfully')
except Exception as e:
    print(f'✗ Decryption failed: {e}', file=sys.stderr)
    sys.exit(1)
"

if [ $? -ne 0 ]; then
    log "${RED}✗ Failed to decrypt backup${NC}"
    exit 1
fi

# Wait for database to be ready
log "${BLUE}Waiting for database to be ready...${NC}"
sleep 5

# Check if database is initialized
DB_INITIALIZED=$(docker compose exec -T db psql -U "${POSTGRES_USER:-loomio}" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB:-loomio_production}'" 2>/dev/null || echo "")

if [ "$DB_INITIALIZED" = "1" ]; then
    log "${BLUE}Database exists, restoring...${NC}"
else
    log "${BLUE}Creating database...${NC}"
    docker compose exec -T db psql -U "${POSTGRES_USER:-loomio}" -d postgres -c "CREATE DATABASE ${POSTGRES_DB:-loomio_production};" || true
fi

# Restore database
log "${BLUE}Restoring database to RAM...${NC}"
export PGPASSWORD="${POSTGRES_PASSWORD}"
cat "$DECRYPTED_FILE" | docker compose exec -T db psql -U "${POSTGRES_USER:-loomio}" -d "${POSTGRES_DB:-loomio_production}" 2>&1 | grep -v "^NOTICE:" | grep -v "^SET$" | head -20

if [ ${PIPESTATUS[1]} -eq 0 ]; then
    log "${GREEN}✓ Database restored to RAM successfully${NC}"
else
    log "${RED}✗ Database restore failed${NC}"
    rm -f "$DECRYPTED_FILE"
    exit 1
fi

# Cleanup
rm -f "$DECRYPTED_FILE"

log "${GREEN}═══════════════════════════════════════════════════${NC}"
log "${GREEN}✓ RAM database initialized${NC}"
log "${GREEN}═══════════════════════════════════════════════════${NC}"
log "${GREEN}  Backup age: ${BACKUP_AGE_HOURS} hours${NC}"
log "${YELLOW}  Remember: Data is in RAM and will be lost on restart${NC}"
log "${YELLOW}  Backups run hourly (or per BACKUP_SCHEDULE)${NC}"
