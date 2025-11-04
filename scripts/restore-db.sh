#!/bin/bash
#
# Restore Database from Backup
# Downloads latest encrypted backup from Google Drive (if enabled) and restores to database
#
# This script is for manual database restoration with user confirmation.
# For automatic restoration (RAM mode), use init-ram.sh instead.
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
    . .env
    set +a
else
    log "${RED}✗ .env file not found!${NC}"
    exit 1
fi

log "${BLUE}═══════════════════════════════════════════════════${NC}"
log "${BLUE}  Database Restore${NC}"
log "${BLUE}═══════════════════════════════════════════════════${NC}"

# Use shared restore-last-backup script
log "${BLUE}Preparing latest backup...${NC}"

DECRYPTED_FILE=$(./scripts/restore-last-backup.sh)

if [ $? -ne 0 ] || [ -z "$DECRYPTED_FILE" ]; then
    log "${RED}✗ Failed to prepare backup${NC}"
    exit 1
fi

# Confirm restore
log "${YELLOW}═══════════════════════════════════════════════════${NC}"
log "${YELLOW}⚠ WARNING: This will REPLACE your current database!${NC}"
log "${YELLOW}═══════════════════════════════════════════════════${NC}"
log "${YELLOW}Backup file: $(basename $DECRYPTED_FILE)${NC}"
log "${YELLOW}Database: ${POSTGRES_DB:-loomio_production}${NC}"
echo ""
read -p "Type 'yes' to confirm restore: " confirm

if [ "$confirm" != "yes" ]; then
    log "${GREEN}✓ Restore cancelled${NC}"
    # Cleanup decrypted file
    if [ "${RAILS_ENV}" = "production" ]; then
        # In RAM mode, cleanup is inside container
        docker compose exec -T backup bash -c "rm -f \"$DECRYPTED_FILE\""
    else
        # In disk mode, cleanup is on host
        rm -f "$DECRYPTED_FILE"
    fi
    exit 0
fi

# Stop app services
log "${BLUE}Stopping app services...${NC}"
docker compose stop app worker channels hocuspocus

# Restore database
log "${BLUE}Restoring database...${NC}"

if [ "${RAILS_ENV}" = "production" ]; then
    # RAM mode: restore from backup container
    docker compose exec -T backup bash -c "
        set -e
        DECRYPTED_FILE=\"$DECRYPTED_FILE\"

        if [ ! -f \"\$DECRYPTED_FILE\" ]; then
            echo 'ERROR: Decrypted backup not found'
            exit 1
        fi

        PGPASSWORD='${POSTGRES_PASSWORD}' psql -h db -U '${POSTGRES_USER:-loomio}' -d '${POSTGRES_DB:-loomio_production}' < \"\$DECRYPTED_FILE\"

        # Cleanup
        rm -f \"\$DECRYPTED_FILE\"
        echo 'Restore complete!'
    "
else
    # Disk mode: restore from host
    export PGPASSWORD="${POSTGRES_PASSWORD}"
    cat "$DECRYPTED_FILE" | docker compose exec -T db psql -U "${POSTGRES_USER:-loomio}" -d "${POSTGRES_DB:-loomio_production}"

    # Cleanup decrypted file
    rm -f "$DECRYPTED_FILE"
fi

if [ $? -eq 0 ]; then
    log "${GREEN}✓ Database restored successfully${NC}"
else
    log "${RED}✗ Database restore failed${NC}"
    exit 1
fi

# Restart app services
log "${BLUE}Restarting app services...${NC}"
docker compose start app worker channels hocuspocus

log "${GREEN}═══════════════════════════════════════════════════${NC}"
log "${GREEN}✓ Database restore completed successfully!${NC}"
log "${GREEN}═══════════════════════════════════════════════════${NC}"
