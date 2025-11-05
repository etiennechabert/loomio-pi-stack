#!/bin/bash
# Manual database backup trigger
# Creates encrypted backup in production/backups/

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if backup container is running
log "${BLUE}Checking backup service status...${NC}"
if ! docker ps --filter name=loomio-backup --filter status=running --format '{{.Names}}' | grep -q loomio-backup; then
    log "${RED}✗ Backup container is not running!${NC}"
    log "Start containers with: make start"
    exit 1
fi

# Trigger manual backup
log "${BLUE}Starting manual database backup...${NC}"
if docker exec loomio-backup python3 /app/backup.py; then
    log "${GREEN}✓ Backup completed successfully!${NC}"
else
    log "${RED}✗ Backup failed!${NC}"
    exit 1
fi

# List recent backups
log "${BLUE}Recent backups:${NC}"
ls -lht production/backups/*.sql.enc 2>/dev/null | head -5 || echo "No backups found"

log "${GREEN}To sync to Google Drive: make sync-gdrive${NC}"
