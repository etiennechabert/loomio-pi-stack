#!/bin/bash
# Download latest backup from Google Drive

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

log "${BLUE}Downloading latest backup from Google Drive...${NC}"

# Get environment name
ENV_NAME="${RAILS_ENV:-production}"

# Download from Google Drive using rclone
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

# Download latest backup from environment-specific folder
echo \"Downloading from: ${ENV_NAME}/backups/\"
rclone copy \"gdrive:${ENV_NAME}/backups\" \"/backups\" \
    --config \"\$RCLONE_CONFIG_DIR/rclone.conf\" \
    --max-age 7d \
    --progress

# Cleanup
rm -rf \"\$RCLONE_CONFIG_DIR\"

echo \"✓ Download complete\"
"

if [ $? -eq 0 ]; then
    log "${GREEN}✓ Latest backup downloaded successfully!${NC}"
    log "${BLUE}Available backups:${NC}"
    ls -lht data/production/backups/*.sql.enc 2>/dev/null | head -5 || echo "No backups found"
    log "${GREEN}To restore: make restore${NC}"
else
    log "${RED}✗ Download failed!${NC}"
    exit 1
fi
