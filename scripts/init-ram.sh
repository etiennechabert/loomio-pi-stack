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
    . .env
    set +a
else
    log "${RED}✗ .env file not found!${NC}"
    exit 1
fi

log "${BLUE}═══════════════════════════════════════════════════${NC}"
log "${BLUE}  RAM Database Initialization${NC}"
log "${BLUE}═══════════════════════════════════════════════════${NC}"

# Use shared restore-last-backup script
log "${BLUE}Downloading and decrypting latest backup...${NC}"

DECRYPTED_FILE=$(./scripts/restore-last-backup.sh | tr -d '\r\n' | xargs)

if [ $? -ne 0 ] || [ -z "$DECRYPTED_FILE" ]; then
    log "${RED}✗ Failed to prepare backup${NC}"
    log "${YELLOW}Starting with fresh database...${NC}"
    log "${YELLOW}Run 'make init' to set up a new database${NC}"
    exit 0
fi

log "${BLUE}Decrypted file path: ${DECRYPTED_FILE}${NC}"

# Wait for database to be ready
log "${BLUE}Waiting for database to be ready...${NC}"
sleep 5

# Restore database (all happens inside backup container's tmpfs)
log "${BLUE}Restoring database from RAM...${NC}"

docker compose exec -T backup bash -c "
    set -e

    DECRYPTED_FILE=\"${DECRYPTED_FILE}\"

    echo \"Looking for file: \$DECRYPTED_FILE\"
    echo \"Files in /backups:\"
    ls -lah /backups/ || echo \"Cannot list /backups\"

    if [ ! -f \"\$DECRYPTED_FILE\" ]; then
        echo \"ERROR: Decrypted backup not found at: \$DECRYPTED_FILE\"
        exit 1
    fi

    echo \"✓ Found decrypted backup file\"

    # Check backup age
    BACKUP_AGE_SECONDS=\$(($(date +%s) - \$(stat -c %Y \"\$DECRYPTED_FILE\" 2>/dev/null || stat -f %m \"\$DECRYPTED_FILE\" 2>/dev/null)))
    BACKUP_AGE_HOURS=\$((BACKUP_AGE_SECONDS / 3600))

    if [ \$BACKUP_AGE_HOURS -gt 24 ]; then
        echo \"WARNING: Backup is \${BACKUP_AGE_HOURS} hours old\"
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

# Check if migrations are pending
log "${BLUE}Checking for pending migrations...${NC}"

# Use Rails to check migration status (don't run migrations yet, just check)
if docker compose run --rm app rake db:migrate:status >/dev/null 2>&1; then
    # Command succeeded - check if there are pending migrations
    PENDING_COUNT=$(docker compose run --rm app rake db:migrate:status 2>/dev/null | grep -c "^\s*down" || echo "0")

    if [ "$PENDING_COUNT" = "0" ]; then
        log "${GREEN}✓ No pending migrations${NC}"
        log "${YELLOW}  Database schema is up to date${NC}"
    else
        log "${YELLOW}⚠ Found $PENDING_COUNT pending migration(s)${NC}"

        # Create pre-migration backup for safety
        log "${BLUE}Creating pre-migration backup...${NC}"
        PRE_MIGRATION_BACKUP="/backups/pre-migration-$(date +%Y%m%d-%H%M%S).sql"

        docker compose exec -T backup bash -c "
            PGPASSWORD='${POSTGRES_PASSWORD}' pg_dump -h db -U '${POSTGRES_USER:-loomio}' -d '${POSTGRES_DB:-loomio_production}' > '${PRE_MIGRATION_BACKUP}' 2>&1
        "

        if [ $? -ne 0 ]; then
            log "${YELLOW}⚠ Warning: Pre-migration backup failed, but continuing...${NC}"
        else
            log "${GREEN}✓ Pre-migration backup created: $(basename ${PRE_MIGRATION_BACKUP})${NC}"
        fi

        # Run migrations to update database schema to match current app version
        log "${BLUE}Running database migrations...${NC}"
        docker compose run --rm app rake db:migrate

        if [ $? -ne 0 ]; then
            log "${RED}✗ Database migrations failed!${NC}"
            log "${RED}Attempting to restore pre-migration backup...${NC}"

            # Try to restore pre-migration backup
            docker compose exec -T backup bash -c "
                PGPASSWORD='${POSTGRES_PASSWORD}' psql -h db -U '${POSTGRES_USER:-loomio}' -d '${POSTGRES_DB:-loomio_production}' < '${PRE_MIGRATION_BACKUP}' 2>&1 | head -20
            "

            if [ $? -eq 0 ]; then
                log "${GREEN}✓ Restored pre-migration backup${NC}"
                log "${YELLOW}System rolled back to pre-migration state${NC}"
            else
                log "${RED}✗ Failed to restore pre-migration backup${NC}"
            fi

            log "${RED}Cannot start with failed migrations.${NC}"
            log "${YELLOW}Check app logs for migration errors.${NC}"
            exit 1
        fi

        log "${GREEN}✓ Database migrations completed successfully${NC}"
    fi
else
    log "${RED}✗ Cannot check migration status${NC}"
    log "${YELLOW}Continuing without running migrations (database may be at older schema version)${NC}"
fi

log "${GREEN}═══════════════════════════════════════════════════${NC}"
log "${GREEN}✓ RAM database initialized from Google Drive${NC}"
log "${GREEN}═══════════════════════════════════════════════════${NC}"
log "${YELLOW}  • Database restored from Google Drive → RAM${NC}"
log "${YELLOW}  • Backup kept in RAM for safety${NC}"
log "${YELLOW}  • Hourly backups: RAM → Google Drive${NC}"
log "${YELLOW}  • ZERO SD card writes!${NC}"
