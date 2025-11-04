#!/bin/bash
#
# Unified Data Sync to Google Drive
# Syncs ALL local data (DB backups + user uploads) to Google Drive
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
if [ -z "${GDRIVE_TOKEN}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
    log "${RED}✗ GDRIVE_TOKEN or GDRIVE_FOLDER_ID not set${NC}"
    log "${YELLOW}Configure Google Drive settings in .env to enable sync${NC}"
    exit 1
fi

log "${BLUE}═══════════════════════════════════════════════════${NC}"
log "${BLUE}  Syncing Local Data to Google Drive${NC}"
log "${BLUE}═══════════════════════════════════════════════════${NC}"

# Create rclone config
RCLONE_CONFIG_DIR="/tmp/rclone-config-$$"
mkdir -p "$RCLONE_CONFIG_DIR"

cat > "$RCLONE_CONFIG_DIR/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
token = ${GDRIVE_TOKEN}
root_folder_id = ${GDRIVE_FOLDER_ID}
EOF

# Local data directory
LOCAL_DATA_DIR="./data"

if [ ! -d "$LOCAL_DATA_DIR" ]; then
    log "${RED}✗ Local data directory not found: $LOCAL_DATA_DIR${NC}"
    exit 1
fi

# Sync entire data directory to Google Drive
log "${BLUE}Syncing: $LOCAL_DATA_DIR → gdrive:Backup${NC}"

rclone sync "$LOCAL_DATA_DIR" "gdrive:Backup" \
    --config "$RCLONE_CONFIG_DIR/rclone.conf" \
    --progress \
    --stats 10s \
    --transfers 4 \
    --checkers 8 \
    --fast-list \
    --exclude '.DS_Store' \
    --exclude 'Thumbs.db' \
    --exclude '*.tmp' \
    --exclude '*.log' 2>&1 | while read line; do
        log "$line"
    done

if [ ${PIPESTATUS[0]} -eq 0 ]; then
    # Calculate statistics
    DB_BACKUPS=$(find "$LOCAL_DATA_DIR/db_backup" -type f 2>/dev/null | wc -l | tr -d ' ')
    UPLOAD_SIZE=$(du -sh "$LOCAL_DATA_DIR/uploads" 2>/dev/null | cut -f1 || echo "0")
    UPLOAD_FILES=$(find "$LOCAL_DATA_DIR/uploads" -type f 2>/dev/null | wc -l | tr -d ' ')

    log "${GREEN}═══════════════════════════════════════════════════${NC}"
    log "${GREEN}✓ Data sync completed successfully!${NC}"
    log "${GREEN}═══════════════════════════════════════════════════${NC}"
    log "${GREEN}  DB Backups:  $DB_BACKUPS files${NC}"
    log "${GREEN}  Uploads:     $UPLOAD_FILES files ($UPLOAD_SIZE)${NC}"
else
    log "${RED}✗ Sync failed${NC}"
    rm -rf "$RCLONE_CONFIG_DIR"
    exit 1
fi

# Cleanup
rm -rf "$RCLONE_CONFIG_DIR"

log "${GREEN}✓ All data synced to Google Drive${NC}"
