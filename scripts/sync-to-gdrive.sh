#!/bin/bash
# Sync backups AND user uploads to Google Drive
# Syncs to {environment}/backups/ and {environment}/uploads/
# Writes status file for monitoring

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
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

# Check required variables
if [ -z "${GDRIVE_TOKEN}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
    log "${RED}✗ Google Drive not configured!${NC}"
    log "Run: make init-gdrive"
    # Write error status inside container (don't fail if container not running)
    docker exec loomio-backup bash -c 'echo "error" > /backups/.last_sync_status' 2>/dev/null || true
    exit 1
fi

log "${BLUE}Syncing backups and uploads to Google Drive...${NC}"

# Execute sync inside backup container (uses sync-data.sh which syncs both backups and uploads)
if docker exec loomio-backup bash /app/sync-data.sh; then
    # Write success status with timestamp
    docker exec loomio-backup bash -c 'date +%s > /backups/.last_sync_status'
    log "${GREEN}✓ Data synced to Google Drive successfully!${NC}"
    exit 0
else
    log "${RED}✗ Sync failed!${NC}"
    # Write error status (don't fail if container not running)
    docker exec loomio-backup bash -c 'echo "error" > /backups/.last_sync_status' 2>/dev/null || true
    exit 1
fi
