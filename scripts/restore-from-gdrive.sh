#!/bin/bash
# Complete disaster recovery from Google Drive
# Downloads latest database backup + all user uploads

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
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
    exit 1
fi

log "${BLUE}═══════════════════════════════════════════════════${NC}"
log "${BLUE}  Complete Restore from Google Drive${NC}"
log "${BLUE}═══════════════════════════════════════════════════${NC}"

# Get environment name
ENV_NAME="${RAILS_ENV:-production}"

# Download latest database backup
log "${BLUE}Downloading latest database backup...${NC}"
docker exec loomio-backup bash -c "
set -e

# Create rclone config
RCLONE_CONFIG_DIR=\"/tmp/rclone-config-\$\$\"
mkdir -p \"\$RCLONE_CONFIG_DIR\"

cat > \"\$RCLONE_CONFIG_DIR/rclone.conf\" << EOF
[gdrive]
type = drive
scope = drive
token = ${GDRIVE_TOKEN}
root_folder_id = ${GDRIVE_FOLDER_ID}
EOF

# Find and download latest backup
echo \"Finding latest backup from: ${ENV_NAME}/backups/\"
LATEST_FILE=\$(rclone lsf \"gdrive:${ENV_NAME}/backups\"     --config \"\$RCLONE_CONFIG_DIR/rclone.conf\"     --files-only     --include '*.sql.enc'     | grep -v '.partial'     | sort -r     | head -1)

if [ -z \"\$LATEST_FILE\" ]; then
    echo \"✗ No backup files found in Google Drive\"
    rm -rf \"\$RCLONE_CONFIG_DIR\"
    exit 1
fi

echo \"Downloading: \$LATEST_FILE\"
rclone copy \"gdrive:${ENV_NAME}/backups/\$LATEST_FILE\" \"/backups\"     --config \"\$RCLONE_CONFIG_DIR/rclone.conf\"     --progress

# Cleanup
rm -rf \"\$RCLONE_CONFIG_DIR\"

echo \"✓ Backup downloaded: \$LATEST_FILE\"
"

if [ $? -ne 0 ]; then
    log "${RED}✗ Failed to download backup!${NC}"
    exit 1
fi

log "${GREEN}✓ Database backup downloaded${NC}"

# Download user uploads
log "${BLUE}Downloading user uploads...${NC}"
log "This may take a while depending on upload size..."

# Ensure upload directories exist
mkdir -p data/uploads/storage data/uploads/system data/uploads/files

# Download using docker run with rclone (temporary container)
docker run --rm \
    -v "$(pwd)/data/uploads:/uploads" \
    -e GDRIVE_TOKEN="${GDRIVE_TOKEN}" \
    -e GDRIVE_FOLDER_ID="${GDRIVE_FOLDER_ID}" \
    -e ENV_NAME="${ENV_NAME}" \
    rclone/rclone:latest \
    bash -c '
set -e

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

# Download uploads
echo "Downloading from: ${ENV_NAME}/uploads/"
for upload_dir in storage system files; do
    echo "  → Downloading $upload_dir..."
    rclone sync "gdrive:${ENV_NAME}/uploads/$upload_dir" "/uploads/$upload_dir" \
        --config "$RCLONE_CONFIG_DIR/rclone.conf" \
        --progress
done

# Cleanup
rm -rf "$RCLONE_CONFIG_DIR"

echo "✓ Uploads downloaded"
'

if [ $? -ne 0 ]; then
    log "${YELLOW}⚠ Warning: Failed to download some uploads${NC}"
else
    log "${GREEN}✓ User uploads downloaded${NC}"
fi

log "${GREEN}═══════════════════════════════════════════════════${NC}"
log "${GREEN}  Download complete!${NC}"
log "${GREEN}═══════════════════════════════════════════════════${NC}"
log ""
log "${BLUE}Next steps:${NC}"
log "  1. Run: make restore-backup  (to restore the downloaded backup)"
log "  2. Check uploads are in: data/uploads/"
