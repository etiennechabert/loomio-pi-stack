#!/bin/bash
# Manual database restore from data/production/backups/
# Usage: ./scripts/restore-db-manual.sh [backup_file]

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Load environment
if [ -f .env ]; then
    set -a
    . .env
    set +a
else
    log "${RED}✗ .env file not found!${NC}"
    exit 1
fi

BACKUP_DIR="./data/production/backups"

# Get backup file (from argument or find latest)
if [ -n "$1" ]; then
    BACKUP_FILE="$1"
else
    log "${BLUE}Finding latest backup...${NC}"
    BACKUP_FILE=$(ls -t "${BACKUP_DIR}"/*.sql.enc 2>/dev/null | head -1)
fi

if [ -z "${BACKUP_FILE}" ] || [ ! -f "${BACKUP_FILE}" ]; then
    log "${RED}✗ No backup file found!${NC}"
    log "Available backups:"
    ls -lht "${BACKUP_DIR}"/*.sql.enc 2>/dev/null || echo "  (none)"
    exit 1
fi

log "${BLUE}Backup file: ${BACKUP_FILE}${NC}"

# Confirm restore
log "${YELLOW}═══════════════════════════════════════════════════${NC}"
log "${YELLOW}⚠  WARNING: This will REPLACE your current database!${NC}"
log "${YELLOW}═══════════════════════════════════════════════════${NC}"
read -p "Continue? (yes/no): " CONFIRM

if [ "${CONFIRM}" != "yes" ]; then
    log "Restore cancelled"
    exit 0
fi

# Stop app and worker containers to release database connections
log "${BLUE}Stopping app and worker containers...${NC}"
docker compose stop app worker

# Decrypt backup
log "${BLUE}Decrypting backup...${NC}"
DECRYPTED_FILE="/tmp/restore_$(date +%s).sql"

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

with open('/backups/$(basename ${BACKUP_FILE})', 'rb') as f:
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

# Drop and recreate database
log "${BLUE}Dropping and recreating database...${NC}"
docker exec loomio-db psql -U "${POSTGRES_USER:-loomio}" -d postgres -c "DROP DATABASE IF EXISTS ${POSTGRES_DB:-loomio_production};"
docker exec loomio-db psql -U "${POSTGRES_USER:-loomio}" -d postgres -c "CREATE DATABASE ${POSTGRES_DB:-loomio_production};"

# Restore database
log "${BLUE}Restoring database...${NC}"
docker exec -i loomio-db psql -U "${POSTGRES_USER:-loomio}" -d "${POSTGRES_DB:-loomio_production}" < "${DECRYPTED_FILE}"

if [ $? -eq 0 ]; then
    log "${GREEN}✓ Database restored successfully!${NC}"
    rm -f "${DECRYPTED_FILE}"

    # Restart app and worker containers
    log "${BLUE}Restarting app and worker containers...${NC}"
    docker compose start app worker
    log "${GREEN}✓ Restore complete!${NC}"
else
    log "${RED}✗ Database restore failed!${NC}"
    rm -f "${DECRYPTED_FILE}"

    # Restart containers even on failure
    log "${BLUE}Restarting app and worker containers...${NC}"
    docker compose start app worker
    exit 1
fi
