#!/bin/bash
#
# Loomio File Uploads Sync to Google Drive
# Syncs user-uploaded files to Google Drive for backup
#

set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Log with timestamp
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Check if Google Drive is enabled
if [ "${GDRIVE_ENABLED}" != "true" ]; then
    log "${YELLOW}⚠ Google Drive sync is disabled (GDRIVE_ENABLED != true)${NC}"
    log "${YELLOW}To enable: Set GDRIVE_ENABLED=true in .env${NC}"
    exit 0
fi

# Check required variables
if [ -z "${GDRIVE_CREDENTIALS}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
    log "${RED}✗ GDRIVE_CREDENTIALS or GDRIVE_FOLDER_ID not set${NC}"
    log "${YELLOW}Configure Google Drive settings in .env to enable file sync${NC}"
    exit 1
fi

log "${BLUE}Starting file upload sync to Google Drive...${NC}"

# Paths to sync
STORAGE_PATHS=(
    "/loomio/storage"
    "/loomio/public/system"
    "/loomio/public/files"
)

# Create rclone config
RCLONE_CONFIG_DIR="/tmp/rclone-config"
mkdir -p "$RCLONE_CONFIG_DIR"

cat > "$RCLONE_CONFIG_DIR/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
service_account_credentials = ${GDRIVE_CREDENTIALS}
root_folder_id = ${GDRIVE_FOLDER_ID}
EOF

# Sync each path
for path in "${STORAGE_PATHS[@]}"; do
    if [ ! -d "$path" ]; then
        log "${YELLOW}⚠ Skipping non-existent path: $path${NC}"
        continue
    fi

    # Get folder name for remote path
    folder_name=$(basename "$path")
    remote_path="gdrive:Upload/$folder_name"

    log "${BLUE}Syncing $path → $remote_path${NC}"

    # Run rclone sync with stats
    rclone sync "$path" "$remote_path" \
        --config "$RCLONE_CONFIG_DIR/rclone.conf" \
        --progress \
        --stats 10s \
        --transfers 4 \
        --checkers 8 \
        --fast-list \
        --exclude '.DS_Store' \
        --exclude 'Thumbs.db' \
        --exclude '*.tmp' 2>&1 | while read line; do
            log "$line"
        done

    if [ $? -eq 0 ]; then
        # Get stats
        SIZE=$(du -sh "$path" 2>/dev/null | cut -f1 || echo "unknown")
        FILES=$(find "$path" -type f 2>/dev/null | wc -l || echo "unknown")
        log "${GREEN}✓ Synced $folder_name: $FILES files, $SIZE${NC}"
    else
        log "${RED}✗ Failed to sync $path${NC}"
    fi
done

# Cleanup
rm -rf "$RCLONE_CONFIG_DIR"

log "${GREEN}✓ File upload sync completed${NC}"
