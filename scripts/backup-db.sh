#!/bin/bash
# Manual database backup trigger
# Creates encrypted backup in production/backups/ with user-provided reason

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
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

# Prompt for backup reason
echo ""
echo -e "${YELLOW}Manual Backup${NC}"
echo -e "${YELLOW}=============${NC}"
echo ""
echo "Please provide a reason for this backup."
echo "Examples: 'update-from-v42.0.4', 'before-major-refactor', 'pre-data-migration'"
echo ""
read -p "Enter backup reason: " BACKUP_REASON

if [ -z "$BACKUP_REASON" ]; then
    log "${RED}✗ Backup reason is required!${NC}"
    exit 1
fi

# Trigger manual backup with reason
log "${BLUE}Creating manual backup: ${BACKUP_REASON}${NC}"
if docker exec loomio-backup python3 /app/backup.py --type manual --reason "$BACKUP_REASON"; then
    log "${GREEN}✓ Backup completed successfully!${NC}"
else
    log "${RED}✗ Backup failed!${NC}"
    exit 1
fi

# List recent manual backups
echo ""
log "${BLUE}Recent manual backups:${NC}"
ls -lht data/production/backups/loomio-manual-*.sql.enc 2>/dev/null | head -5 || echo "No manual backups found"

echo ""
log "${YELLOW}Note: Manual backups are never automatically deleted${NC}"
log "${GREEN}To upload to Google Drive: make upload-to-gdrive${NC}"
