#!/bin/bash
# Sync backups to Google Drive at production/backups/
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

STATUS_FILE="./production/backups/.last_sync_status"

# Load environment
if [ -f .env ]; then
    set -a
    . .env
    set +a
else
    log "${RED}✗ .env file not found!${NC}"
    echo "error" > "${STATUS_FILE}"
    exit 1
fi

# Check required variables
if [ -z "${GDRIVE_TOKEN}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
    log "${RED}✗ Google Drive not configured!${NC}"
    log "Run: make init-gdrive"
    echo "error" > "${STATUS_FILE}"
    exit 1
fi

log "${BLUE}Syncing backups to Google Drive...${NC}"

# Execute sync inside backup container
if docker exec loomio-backup bash -c '
set -e

# Create rclone config
RCLONE_CONFIG_DIR="/tmp/rclone-config-$$"
mkdir -p "$RCLONE_CONFIG_DIR"

cat > "$RCLONE_CONFIG_DIR/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
token = '""'
root_folder_id = '""'
EOF

# Sync backups to production/backups/ in Google Drive
echo "Uploading to Google Drive: production/backups/"
rclone sync "/backups" "gdrive:production/backups"     --config "$RCLONE_CONFIG_DIR/rclone.conf"     --transfers 4     --checkers 8     --fast-list     --exclude ".DS_Store"     --exclude "Thumbs.db"     --exclude "*.tmp"     --exclude ".last_sync_status"     --progress

# Cleanup
rm -rf "$RCLONE_CONFIG_DIR"

echo "✓ Sync completed"
'; then
    log "${GREEN}✓ Backups synced to Google Drive successfully!${NC}"
    # Write success status with timestamp
    date +%s > "${STATUS_FILE}"
    exit 0
else
    log "${RED}✗ Sync failed!${NC}"
    # Write error status
    echo "error" > "${STATUS_FILE}"
    exit 1
fi
