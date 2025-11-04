#!/bin/bash
#
# Restore User Uploads from Google Drive
# Downloads all user-uploaded files from Google Drive backup
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

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    log "${RED}✗ .env file not found!${NC}"
    exit 1
fi

# Check if Google Drive is enabled
if [ "${GDRIVE_ENABLED}" != "true" ]; then
    log "${RED}✗ Google Drive is disabled (GDRIVE_ENABLED != true)${NC}"
    log "${YELLOW}Enable Google Drive in .env to restore uploads${NC}"
    exit 1
fi

# Check required variables
if [ -z "${GDRIVE_TOKEN}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
    log "${RED}✗ GDRIVE_TOKEN or GDRIVE_FOLDER_ID not set${NC}"
    log "${YELLOW}Configure Google Drive settings in .env${NC}"
    exit 1
fi

log "${BLUE}═══════════════════════════════════════════════════${NC}"
log "${BLUE}  Restore User Uploads from Google Drive${NC}"
log "${BLUE}═══════════════════════════════════════════════════${NC}"

LOCAL_UPLOADS_DIR="./data/uploads"
mkdir -p "$LOCAL_UPLOADS_DIR"

# Confirm restore
log "${YELLOW}═══════════════════════════════════════════════════${NC}"
log "${YELLOW}⚠ WARNING: This will overwrite local uploads!${NC}"
log "${YELLOW}═══════════════════════════════════════════════════${NC}"
log "${YELLOW}Target: $LOCAL_UPLOADS_DIR${NC}"
echo ""
read -p "Type 'yes' to confirm restore: " confirm

if [ "$confirm" != "yes" ]; then
    log "${GREEN}✓ Restore cancelled${NC}"
    exit 0
fi

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

# Download uploads from Google Drive
log "${BLUE}Downloading uploads from Google Drive...${NC}"

rclone sync "gdrive:Backup/uploads" "$LOCAL_UPLOADS_DIR" \
    --config "$RCLONE_CONFIG_DIR/rclone.conf" \
    --progress \
    --stats 10s \
    --transfers 4 \
    --checkers 8 \
    --fast-list

if [ $? -eq 0 ]; then
    # Calculate statistics
    UPLOAD_SIZE=$(du -sh "$LOCAL_UPLOADS_DIR" 2>/dev/null | cut -f1 || echo "0")
    UPLOAD_FILES=$(find "$LOCAL_UPLOADS_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')

    log "${GREEN}═══════════════════════════════════════════════════${NC}"
    log "${GREEN}✓ Uploads restored successfully!${NC}"
    log "${GREEN}═══════════════════════════════════════════════════${NC}"
    log "${GREEN}  Files:  $UPLOAD_FILES${NC}"
    log "${GREEN}  Size:   $UPLOAD_SIZE${NC}"
else
    log "${RED}✗ Failed to download uploads${NC}"
    rm -rf "$RCLONE_CONFIG_DIR"
    exit 1
fi

# Cleanup
rm -rf "$RCLONE_CONFIG_DIR"

# Set proper permissions
log "${BLUE}Setting permissions...${NC}"
chmod -R 755 "$LOCAL_UPLOADS_DIR"

log "${GREEN}✓ All uploads restored from Google Drive${NC}"
log "${YELLOW}Note: Restart Loomio services to ensure uploads are accessible${NC}"
log "${YELLOW}Run: docker compose restart app worker${NC}"
