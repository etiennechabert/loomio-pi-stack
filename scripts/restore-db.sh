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
log "${YELLOW}Backup file: $(basename "$DECRYPTED_FILE")${NC}"
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

# Create pre-migration backup for safety
log "${BLUE}Creating pre-migration backup...${NC}"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

if [ "${RAILS_ENV}" = "production" ]; then
    # RAM mode: backup in container
    PRE_MIGRATION_BACKUP="/backups/pre-migration-${TIMESTAMP}.sql"
    docker compose exec -T backup bash -c "
        PGPASSWORD='${POSTGRES_PASSWORD}' pg_dump -h db -U '${POSTGRES_USER:-loomio}' -d '${POSTGRES_DB:-loomio_production}' > '${PRE_MIGRATION_BACKUP}' 2>&1
    "
else
    # Disk mode: backup to data directory
    PRE_MIGRATION_BACKUP="./data/db_backup/pre-migration-${TIMESTAMP}.sql"
    mkdir -p ./data/db_backup
    export PGPASSWORD="${POSTGRES_PASSWORD}"
    docker compose exec -T db pg_dump -U "${POSTGRES_USER:-loomio}" -d "${POSTGRES_DB:-loomio_production}" > "${PRE_MIGRATION_BACKUP}"
fi

if [ $? -ne 0 ]; then
    log "${YELLOW}⚠ Warning: Pre-migration backup failed${NC}"
else
    log "${GREEN}✓ Pre-migration backup created${NC}"
fi

# Run migrations to update database schema to match current app version
log "${BLUE}Running database migrations...${NC}"
docker compose run --rm app rake db:migrate

if [ $? -ne 0 ]; then
    log "${RED}✗ Database migrations failed!${NC}"
    log "${RED}Attempting to restore pre-migration backup...${NC}"

    # Try to restore pre-migration backup
    if [ -n "${PRE_MIGRATION_BACKUP}" ]; then
        if [ "${RAILS_ENV}" = "production" ]; then
            docker compose exec -T backup bash -c "
                PGPASSWORD='${POSTGRES_PASSWORD}' psql -h db -U '${POSTGRES_USER:-loomio}' -d '${POSTGRES_DB:-loomio_production}' < '${PRE_MIGRATION_BACKUP}' 2>&1 | head -20
            "
        else
            export PGPASSWORD="${POSTGRES_PASSWORD}"
            cat "${PRE_MIGRATION_BACKUP}" | docker compose exec -T db psql -U "${POSTGRES_USER:-loomio}" -d "${POSTGRES_DB:-loomio_production}"
        fi

        if [ $? -eq 0 ]; then
            log "${GREEN}✓ Restored pre-migration backup${NC}"
            log "${YELLOW}Database rolled back to pre-migration state${NC}"
        else
            log "${RED}✗ Failed to restore pre-migration backup${NC}"
        fi
    fi

    log "${RED}Cannot restart services with failed migrations.${NC}"
    log "${YELLOW}Services remain stopped. Check app logs for migration errors.${NC}"
    exit 1
fi

log "${GREEN}✓ Database migrations completed successfully${NC}"

# Restart app services
log "${BLUE}Restarting app services...${NC}"
docker compose start app worker channels hocuspocus

log "${GREEN}═══════════════════════════════════════════════════${NC}"
log "${GREEN}✓ Database restore completed successfully!${NC}"
log "${GREEN}═══════════════════════════════════════════════════${NC}"
