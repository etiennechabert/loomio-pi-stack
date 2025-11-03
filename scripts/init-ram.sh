#!/bin/bash
#
# Initialize RAM-based Database
# Downloads latest backup from Google Drive directly to RAM and restores
#
# In RAM mode, backups are stored ONLY in RAM and Google Drive (not on disk)
# This minimizes SD card writes completely.
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

# In RAM mode, backups are stored in tmpfs inside the backup container
# We need to download from Google Drive into the backup container's /backups (tmpfs)
TMPFS_BACKUP_DIR="/backups"

# Check if Google Drive is configured (MANDATORY in production/RAM mode)
if [ "${GDRIVE_ENABLED}" != "true" ] || [ -z "${GDRIVE_CREDENTIALS}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
    log "${RED}✗ ERROR: Google Drive is MANDATORY in production (RAM mode)!${NC}"
    log "${RED}  In production, backups are stored only in RAM + Google Drive${NC}"
    log "${RED}  Without Google Drive, there is NO persistence!${NC}"
    log ""
    log "${YELLOW}To fix:${NC}"
    log "  1. Set GDRIVE_ENABLED=true in .env"
    log "  2. Configure GDRIVE_CREDENTIALS (service account JSON)"
    log "  3. Configure GDRIVE_FOLDER_ID"
    log ""
    log "${YELLOW}Or switch to development mode:${NC}"
    log "  1. Set RAILS_ENV=development in .env"
    log "  2. Restart: make down && make start"
    exit 1
fi

log "${BLUE}Downloading latest backup from Google Drive to RAM...${NC}"

# Download latest backup from Google Drive directly into backup container's tmpfs
docker compose exec -T backup bash -c "
    set -e

    # Create rclone config
    RCLONE_CONFIG_DIR=\"/tmp/rclone-config-\$\$\"
    mkdir -p \"\$RCLONE_CONFIG_DIR\"

    cat > \"\$RCLONE_CONFIG_DIR/rclone.conf\" << 'RCLONE_EOF'
[gdrive]
type = drive
scope = drive
service_account_credentials = ${GDRIVE_CREDENTIALS}
root_folder_id = ${GDRIVE_FOLDER_ID}
RCLONE_EOF

    # Download latest backup to tmpfs
    echo 'Downloading from Google Drive...'
    rclone copy 'gdrive:Backup/db_backup' '${TMPFS_BACKUP_DIR}' \
        --config \"\$RCLONE_CONFIG_DIR/rclone.conf\" \
        --max-age 7d \
        --progress

    rm -rf \"\$RCLONE_CONFIG_DIR\"

    # Check if we got a backup
    BACKUP_COUNT=\$(ls -1 ${TMPFS_BACKUP_DIR}/loomio_backup_*.sql.enc 2>/dev/null | wc -l)
    if [ \$BACKUP_COUNT -eq 0 ]; then
        echo 'ERROR: No backup found in Google Drive'
        exit 1
    fi

    echo 'Download complete!'
"

if [ $? -ne 0 ]; then
    log "${RED}✗ Failed to download backup from Google Drive${NC}"
    log "${YELLOW}Starting with fresh database...${NC}"
    log "${YELLOW}Run 'make init' to set up a new database${NC}"
    exit 0
fi

# Get the latest backup filename from the backup container
LATEST_BACKUP=$(docker compose exec -T backup bash -c "ls -t ${TMPFS_BACKUP_DIR}/loomio_backup_*.sql.enc 2>/dev/null | head -1" | tr -d '\r')

if [ -z "$LATEST_BACKUP" ]; then
    log "${RED}✗ No backup found in RAM after download${NC}"
    log "${YELLOW}Starting with fresh database...${NC}"
    exit 0
fi

log "${GREEN}✓ Downloaded backup to RAM: $(basename $LATEST_BACKUP)${NC}"

# Wait for database to be ready
log "${BLUE}Waiting for database to be ready...${NC}"
sleep 5

# Decrypt and restore backup (all happens inside backup container's tmpfs)
log "${BLUE}Decrypting and restoring backup from RAM...${NC}"

docker compose exec -T backup bash -c "
    set -e

    LATEST_BACKUP=\"\$(ls -t ${TMPFS_BACKUP_DIR}/loomio_backup_*.sql.enc 2>/dev/null | head -1)\"

    if [ -z \"\$LATEST_BACKUP\" ]; then
        echo 'ERROR: No backup found in RAM'
        exit 1
    fi

    echo \"Using backup: \$(basename \$LATEST_BACKUP)\"

    # Check backup age
    BACKUP_AGE_SECONDS=\$(($(date +%s) - \$(stat -c %Y \"\$LATEST_BACKUP\" 2>/dev/null)))
    BACKUP_AGE_HOURS=\$((BACKUP_AGE_SECONDS / 3600))

    if [ \$BACKUP_AGE_HOURS -gt 24 ]; then
        echo \"WARNING: Backup is \${BACKUP_AGE_HOURS} hours old\"
    fi

    # Decrypt backup in RAM
    DECRYPTED_FILE=\"\${LATEST_BACKUP%.enc}\"

    python3 -c \"
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

    with open('\$LATEST_BACKUP', 'rb') as f:
        encrypted_data = f.read()

    decrypted_data = fernet.decrypt(encrypted_data)

    with open('\$DECRYPTED_FILE', 'wb') as f:
        f.write(decrypted_data)

    print('✓ Decrypted successfully')
except Exception as e:
    print(f'✗ Decryption failed: {e}', file=sys.stderr)
    sys.exit(1)
\"

    if [ \$? -ne 0 ]; then
        echo 'ERROR: Decryption failed'
        exit 1
    fi

    # Check if database exists
    DB_INITIALIZED=\$(PGPASSWORD='${POSTGRES_PASSWORD}' psql -h db -U '${POSTGRES_USER:-loomio}' -d postgres -tAc \"SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB:-loomio_production}'\" 2>/dev/null || echo \"\")

    if [ \"\$DB_INITIALIZED\" != \"1\" ]; then
        echo 'Creating database...'
        PGPASSWORD='${POSTGRES_PASSWORD}' psql -h db -U '${POSTGRES_USER:-loomio}' -d postgres -c \"CREATE DATABASE ${POSTGRES_DB:-loomio_production};\" || true
    fi

    # Restore database from RAM backup
    echo 'Restoring database...'
    PGPASSWORD='${POSTGRES_PASSWORD}' psql -h db -U '${POSTGRES_USER:-loomio}' -d '${POSTGRES_DB:-loomio_production}' < \"\$DECRYPTED_FILE\" 2>&1 | grep -v '^NOTICE:' | grep -v '^SET\$' | head -20

    # Cleanup decrypted file (keep encrypted backup in RAM for next cycle)
    rm -f \"\$DECRYPTED_FILE\"

    echo 'Restore complete!'
"

if [ $? -ne 0 ]; then
    log "${RED}✗ Database restore failed${NC}"
    exit 1
fi

log "${GREEN}═══════════════════════════════════════════════════${NC}"
log "${GREEN}✓ RAM database initialized from Google Drive${NC}"
log "${GREEN}═══════════════════════════════════════════════════${NC}"
log "${YELLOW}  • Database restored from Google Drive → RAM${NC}"
log "${YELLOW}  • Backup kept in RAM for safety${NC}"
log "${YELLOW}  • Hourly backups: RAM → Google Drive${NC}"
log "${YELLOW}  • ZERO SD card writes!${NC}"
