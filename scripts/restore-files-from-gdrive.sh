#!/bin/bash
#
# Loomio File Uploads Restore from Google Drive
# Restores user-uploaded files from Google Drive backup
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
    log "${RED}✗ Google Drive is not enabled${NC}"
    log "${YELLOW}Set GDRIVE_ENABLED=true in .env to use Google Drive restore${NC}"
    exit 1
fi

# Check required variables
if [ -z "${GDRIVE_CREDENTIALS}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
    log "${RED}✗ GDRIVE_CREDENTIALS or GDRIVE_FOLDER_ID not set${NC}"
    exit 1
fi

log "${RED}═══════════════════════════════════════════════════════════════${NC}"
log "${RED}        RESTORE FILE UPLOADS FROM GOOGLE DRIVE                 ${NC}"
log "${RED}═══════════════════════════════════════════════════════════════${NC}"
echo ""
log "${YELLOW}⚠ WARNING: This will restore files from Google Drive backup${NC}"
log "${YELLOW}⚠ WARNING: Existing files will be synchronized${NC}"
echo ""
read -p "Type 'yes' to confirm restore: " confirm

if [ "$confirm" != "yes" ]; then
    log "${GREEN}✓ Operation cancelled${NC}"
    exit 0
fi

log "${BLUE}Starting file restore from Google Drive...${NC}"

# Paths to restore
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

# Restore each path
for path in "${STORAGE_PATHS[@]}"; do
    # Create directory if it doesn't exist
    mkdir -p "$path"

    # Get folder name for remote path
    folder_name=$(basename "$path")
    remote_path="gdrive:Upload/$folder_name"

    log "${BLUE}Restoring $remote_path → $path${NC}"

    # Check if remote exists
    rclone lsd "$remote_path" --config "$RCLONE_CONFIG_DIR/rclone.conf" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "${YELLOW}⚠ No backup found for $folder_name, skipping${NC}"
        continue
    fi

    # Run rclone sync (from Google Drive to local)
    rclone sync "$remote_path" "$path" \
        --config "$RCLONE_CONFIG_DIR/rclone.conf" \
        --progress \
        --stats 10s \
        --transfers 4 \
        --checkers 8 \
        --fast-list 2>&1 | while read line; do
            log "$line"
        done

    if [ $? -eq 0 ]; then
        SIZE=$(du -sh "$path" 2>/dev/null | cut -f1 || echo "unknown")
        FILES=$(find "$path" -type f 2>/dev/null | wc -l || echo "unknown")
        log "${GREEN}✓ Restored $folder_name: $FILES files, $SIZE${NC}"
    else
        log "${RED}✗ Failed to restore $path${NC}"
    fi
done

# Cleanup
rm -rf "$RCLONE_CONFIG_DIR"

log "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
log "${GREEN}  ✓ File restore completed                                     ${NC}"
log "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
log "${YELLOW}Important: Restart Loomio for changes to take effect:${NC}"
log "  make restart"
