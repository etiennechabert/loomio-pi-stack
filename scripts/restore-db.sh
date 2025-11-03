#!/bin/bash
#
# Restore Database from Google Drive Backup
# Downloads latest encrypted backup from Google Drive and restores to database
#

set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Log with timestamp
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    log "${RED}✗ .env file not found!${NC}"
    exit 1
fi

# Check required variables
if [ -z "${BACKUP_ENCRYPTION_KEY}" ]; then
    log "${RED}✗ BACKUP_ENCRYPTION_KEY not set in .env${NC}"
    exit 1
fi

if [ "${GDRIVE_ENABLED}" != "true" ]; then
    log "${YELLOW}⚠ Google Drive is disabled. Restoring from local backup...${NC}"
    RESTORE_FROM_LOCAL=true
else
    if [ -z "${GDRIVE_CREDENTIALS}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
        log "${YELLOW}⚠ Google Drive not configured. Restoring from local backup...${NC}"
        RESTORE_FROM_LOCAL=true
    else
        RESTORE_FROM_LOCAL=false
    fi
fi

log "${BLUE}═══════════════════════════════════════════════════${NC}"
log "${BLUE}  Database Restore${NC}"
log "${BLUE}═══════════════════════════════════════════════════${NC}"

LOCAL_BACKUP_DIR="./data/db_backup"
mkdir -p "$LOCAL_BACKUP_DIR"

# Download from Google Drive if enabled
if [ "$RESTORE_FROM_LOCAL" = false ]; then
    log "${BLUE}Downloading latest backup from Google Drive...${NC}"

    # Create rclone config
    RCLONE_CONFIG_DIR="/tmp/rclone-config-$$"
    mkdir -p "$RCLONE_CONFIG_DIR"

    cat > "$RCLONE_CONFIG_DIR/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
service_account_credentials = ${GDRIVE_CREDENTIALS}
root_folder_id = ${GDRIVE_FOLDER_ID}
EOF

    # Download entire db_backup folder from Google Drive
    rclone sync "gdrive:Backup/db_backup" "$LOCAL_BACKUP_DIR" \
        --config "$RCLONE_CONFIG_DIR/rclone.conf" \
        --progress

    if [ $? -eq 0 ]; then
        log "${GREEN}✓ Downloaded backups from Google Drive${NC}"
    else
        log "${RED}✗ Failed to download from Google Drive${NC}"
        rm -rf "$RCLONE_CONFIG_DIR"
        exit 1
    fi

    rm -rf "$RCLONE_CONFIG_DIR"
fi

# Find latest backup
LATEST_BACKUP=$(ls -t "$LOCAL_BACKUP_DIR"/loomio_backup_*.sql.enc 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
    log "${RED}✗ No backup files found in $LOCAL_BACKUP_DIR${NC}"
    exit 1
fi

log "${BLUE}Using backup: $(basename $LATEST_BACKUP)${NC}"

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

    print('✓ Backup decrypted successfully')
except Exception as e:
    print(f'✗ Decryption failed: {e}', file=sys.stderr)
    sys.exit(1)
"

if [ $? -ne 0 ]; then
    log "${RED}✗ Failed to decrypt backup${NC}"
    exit 1
fi

# Confirm restore
log "${YELLOW}═══════════════════════════════════════════════════${NC}"
log "${YELLOW}⚠ WARNING: This will REPLACE your current database!${NC}"
log "${YELLOW}═══════════════════════════════════════════════════${NC}"
log "${YELLOW}Backup file: $(basename $LATEST_BACKUP)${NC}"
log "${YELLOW}Database: ${POSTGRES_DB:-loomio_production}${NC}"
echo ""
read -p "Type 'yes' to confirm restore: " confirm

if [ "$confirm" != "yes" ]; then
    log "${GREEN}✓ Restore cancelled${NC}"
    rm -f "$DECRYPTED_FILE"
    exit 0
fi

# Stop app services
log "${BLUE}Stopping app services...${NC}"
docker compose stop app worker channels hocuspocus

# Restore database
log "${BLUE}Restoring database...${NC}"

export PGPASSWORD="${POSTGRES_PASSWORD}"
cat "$DECRYPTED_FILE" | docker compose exec -T db psql -U "${POSTGRES_USER:-loomio}" -d "${POSTGRES_DB:-loomio_production}"

if [ $? -eq 0 ]; then
    log "${GREEN}✓ Database restored successfully${NC}"
else
    log "${RED}✗ Database restore failed${NC}"
    rm -f "$DECRYPTED_FILE"
    exit 1
fi

# Cleanup decrypted file
rm -f "$DECRYPTED_FILE"

# Restart app services
log "${BLUE}Restarting app services...${NC}"
docker compose start app worker channels hocuspocus

log "${GREEN}═══════════════════════════════════════════════════${NC}"
log "${GREEN}✓ Database restore completed successfully!${NC}"
log "${GREEN}═══════════════════════════════════════════════════${NC}"
