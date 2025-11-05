#!/bin/bash
# Restore latest backup on boot (automatic)
# Checks local production/backups/ first, then downloads from Google Drive if needed

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/production/backups"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Load environment
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

log "${BLUE}═══════════════════════════════════════════════════${NC}"
log "${BLUE}  Auto-Restore on Boot${NC}"
log "${BLUE}═══════════════════════════════════════════════════${NC}"

# Check if database is empty
log "Checking database status..."
TABLE_COUNT=$(docker exec loomio-db psql -U "${POSTGRES_USER:-loomio}" -d "${POSTGRES_DB:-loomio_production}" -t -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null | tr -d ' ' || echo "0")

if [ "$TABLE_COUNT" -gt "0" ]; then
    log "${GREEN}✓ Database already populated ($TABLE_COUNT tables)${NC}"
    log "Skipping restore"
    exit 0
fi

log "${YELLOW}Database is empty - restore required${NC}"

# Look for latest backup locally
log "Looking for local backups in ${BACKUP_DIR}/..."
LATEST_BACKUP=$(ls -t "${BACKUP_DIR}"/*.sql.enc 2>/dev/null | head -1)

# If no local backup, download from Google Drive
if [ -z "${LATEST_BACKUP}" ]; then
    log "${YELLOW}No local backup found${NC}"
    
    if [ -z "${GDRIVE_TOKEN}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
        log "${RED}✗ Google Drive not configured and no local backup!${NC}"
        log "Cannot restore database"
        exit 1
    fi
    
    log "${BLUE}Downloading latest backup from Google Drive...${NC}"

    # Get environment name
    ENV_NAME="${RAILS_ENV:-production}"

    # Download from Google Drive using rclone
    docker exec loomio-backup bash -c "
        set -e

        # Create rclone config
        RCLONE_CONFIG_DIR=\"/tmp/rclone-config-$$\"
        mkdir -p \"\$RCLONE_CONFIG_DIR\"

        cat > \"\$RCLONE_CONFIG_DIR/rclone.conf\" << EOF
[gdrive]
type = drive
scope = drive
token = ${GDRIVE_TOKEN}
root_folder_id = ${GDRIVE_FOLDER_ID}
EOF

        # Download latest backup from environment-specific folder
        rclone copy \"gdrive:production/backups/${ENV_NAME}\" \"/backups\"             --config \"\$RCLONE_CONFIG_DIR/rclone.conf\"             --max-age 7d             --progress

        # Cleanup
        rm -rf \"\$RCLONE_CONFIG_DIR\"
    "
    
    # Check if download succeeded
    LATEST_BACKUP=$(ls -t "${BACKUP_DIR}"/*.sql.enc 2>/dev/null | head -1)
    
    if [ -z "${LATEST_BACKUP}" ]; then
        log "${RED}✗ Failed to download backup from Google Drive!${NC}"
        exit 1
    fi
    
    log "${GREEN}✓ Downloaded backup from Google Drive${NC}"
fi

log "${BLUE}Latest backup: $(basename "$LATEST_BACKUP")${NC}"

# Decrypt backup
log "Decrypting backup..."
DECRYPTED_FILE="/tmp/restore_boot_$(date +%s).sql"

docker exec loomio-backup python3 -c "
import sys
from cryptography.fernet import Fernet
import base64
import hashlib

def derive_fernet_key(password):
    kdf_output = hashlib.pbkdf2_hmac('sha256', password.encode(), b'loomio-backup-salt', 100000, dklen=32)
    return base64.urlsafe_b64encode(kdf_output)

key = '${BACKUP_ENCRYPTION_KEY}'
fernet_key = derive_fernet_key(key)
fernet = Fernet(fernet_key)

with open('/backups/$(basename ${LATEST_BACKUP})', 'rb') as f:
    encrypted = f.read()

decrypted = fernet.decrypt(encrypted)

with open('${DECRYPTED_FILE}', 'wb') as f:
    f.write(decrypted)

print('Decrypted')
"

if [ $? -ne 0 ]; then
    log "${RED}✗ Decryption failed!${NC}"
    exit 1
fi

# Restore database
log "Restoring database..."
docker exec -i loomio-db psql -U "${POSTGRES_USER:-loomio}" -d "${POSTGRES_DB:-loomio_production}" < "${DECRYPTED_FILE}" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    log "${GREEN}✓ Database restored successfully!${NC}"
    rm -f "${DECRYPTED_FILE}"
else
    log "${RED}✗ Database restore failed!${NC}"
    rm -f "${DECRYPTED_FILE}"
    exit 1
fi

log "${GREEN}═══════════════════════════════════════════════════${NC}"
log "${GREEN}  Boot restore completed!${NC}"
log "${GREEN}═══════════════════════════════════════════════════${NC}"
