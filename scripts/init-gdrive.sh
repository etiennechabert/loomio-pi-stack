#!/bin/bash
#
# Initialize and Validate Google Drive Setup for Loomio
# Creates folder structure and tests connectivity
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

log "${BLUE}╔═══════════════════════════════════════════════════════════════${NC}"
log "${BLUE}║      Google Drive Initialization & Validation                ║${NC}"
log "${BLUE}╚═══════════════════════════════════════════════════════════════${NC}"
echo ""

# Load environment variables
if [ -f .env ]; then
    set -a
    . .env
    set +a
else
    log "${RED}✗ .env file not found${NC}"
    exit 1
fi

# Check if Google Drive is enabled
if [ "${GDRIVE_ENABLED}" != "true" ]; then
    log "${RED}✗ Google Drive is not enabled${NC}"
    log "${YELLOW}Set GDRIVE_ENABLED=true in .env${NC}"
    exit 1
fi

# Check required variables
if [ -z "${GDRIVE_CREDENTIALS}" ]; then
    log "${RED}✗ GDRIVE_CREDENTIALS not set${NC}"
    log "${YELLOW}Configure service account JSON in .env${NC}"
    exit 1
fi

if [ -z "${GDRIVE_FOLDER_ID}" ]; then
    log "${RED}✗ GDRIVE_FOLDER_ID not set${NC}"
    log "${YELLOW}Create a folder in Google Drive and add its ID to .env${NC}"
    exit 1
fi

log "${GREEN}✓ Configuration variables found${NC}"
echo ""

# Create rclone config
RCLONE_CONFIG_DIR="/tmp/rclone-config-$$"
mkdir -p "$RCLONE_CONFIG_DIR"

cat > "$RCLONE_CONFIG_DIR/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
service_account_credentials = ${GDRIVE_CREDENTIALS}
root_folder_id = ${GDRIVE_FOLDER_ID}
EOF

log "${BLUE}Step 1: Testing Google Drive connectivity...${NC}"

# Test connection
if ! rclone lsd gdrive: --config "$RCLONE_CONFIG_DIR/rclone.conf" > /dev/null 2>&1; then
    log "${RED}✗ Failed to connect to Google Drive${NC}"
    log "${YELLOW}Check your GDRIVE_CREDENTIALS and GDRIVE_FOLDER_ID${NC}"
    rm -rf "$RCLONE_CONFIG_DIR"
    exit 1
fi

log "${GREEN}✓ Successfully connected to Google Drive${NC}"
echo ""

log "${BLUE}Step 2: Creating folder structure...${NC}"

# Get environment name
ENV_NAME="${RAILS_ENV:-production}"

# Create production/backups/{environment} folder structure
log "  Creating: production/backups/${ENV_NAME}/"
rclone mkdir "gdrive:production/backups/${ENV_NAME}" --config "$RCLONE_CONFIG_DIR/rclone.conf" 2>/dev/null || true

# Create Upload folder with subfolders
log "  Creating: Upload/"
rclone mkdir gdrive:Upload --config "$RCLONE_CONFIG_DIR/rclone.conf" 2>/dev/null || true

log "  Creating: Upload/storage/"
rclone mkdir gdrive:Upload/storage --config "$RCLONE_CONFIG_DIR/rclone.conf" 2>/dev/null || true

log "  Creating: Upload/system/"
rclone mkdir gdrive:Upload/system --config "$RCLONE_CONFIG_DIR/rclone.conf" 2>/dev/null || true

log "  Creating: Upload/files/"
rclone mkdir gdrive:Upload/files --config "$RCLONE_CONFIG_DIR/rclone.conf" 2>/dev/null || true

log "${GREEN}✓ Folder structure created${NC}"
echo ""

log "${BLUE}Step 3: Creating test files...${NC}"

# Create test file
TEST_FILE="/tmp/loomio-gdrive-test-$$.txt"
cat > "$TEST_FILE" << TESTEOF
Loomio Google Drive Test
========================

This file was created by the init-gdrive script to verify:
- Google Drive connectivity
- Write permissions
- Folder structure

Timestamp: $(date)
Host: $(hostname)
User: $(whoami)

If you can see this file in Google Drive, the setup is working correctly!
TESTEOF

# Upload test file to Backup folder
log "  Uploading test file to production/backups/${ENV_NAME}/..."
if rclone copy "$TEST_FILE" "gdrive:production/backups/${ENV_NAME}/" --config "$RCLONE_CONFIG_DIR/rclone.conf"; then
    log "${GREEN}✓ Test file uploaded to production/backups/${ENV_NAME}/${NC}"
else
    log "${RED}✗ Failed to upload test file${NC}"
    rm -rf "$RCLONE_CONFIG_DIR" "$TEST_FILE"
    exit 1
fi

# Upload test file to Upload folder
log "  Uploading test file to Upload/storage/..."
if rclone copy "$TEST_FILE" gdrive:Upload/storage/ --config "$RCLONE_CONFIG_DIR/rclone.conf"; then
    log "${GREEN}✓ Test file uploaded to Upload/storage/${NC}"
else
    log "${RED}✗ Failed to upload test file${NC}"
    rm -rf "$RCLONE_CONFIG_DIR" "$TEST_FILE"
    exit 1
fi

rm "$TEST_FILE"

echo ""
log "${BLUE}Step 4: Verifying folder structure...${NC}"

# List folders
log ""
log "${YELLOW}Folder structure in Google Drive:${NC}"
rclone lsd gdrive: --config "$RCLONE_CONFIG_DIR/rclone.conf" | while read line; do
    log "  $line"
done

log ""
log "${YELLOW}Upload subfolders:${NC}"
rclone lsd gdrive:Upload/ --config "$RCLONE_CONFIG_DIR/rclone.conf" | while read line; do
    log "  $line"
done

echo ""
log "${BLUE}Step 5: Testing download (verify read access)...${NC}"

# Download test file
DOWNLOAD_FILE="/tmp/loomio-gdrive-download-$$.txt"
if rclone copy "gdrive:production/backups/${ENV_NAME}/loomio-gdrive-test-$$.txt" "$DOWNLOAD_FILE" --config "$RCLONE_CONFIG_DIR/rclone.conf"; then
    log "${GREEN}✓ Successfully downloaded test file${NC}"
    rm -f "$DOWNLOAD_FILE"/*.txt
    rmdir "$DOWNLOAD_FILE" 2>/dev/null || true
else
    log "${YELLOW}⚠ Download test skipped or failed${NC}"
fi

# Cleanup
rm -rf "$RCLONE_CONFIG_DIR"

echo ""
log "${GREEN}╔═══════════════════════════════════════════════════════════════${NC}"
log "${GREEN}║              ✓ Google Drive Setup Complete!                  ║${NC}"
log "${GREEN}╚═══════════════════════════════════════════════════════════════${NC}"
echo ""
log "${YELLOW}Folder Structure Created:${NC}"
log "  📁 production/backups/${ENV_NAME}/  - Database backups (environment-specific)"
log "  📁 Upload/                          - File uploads go here"
log "     📁 storage/                      - Active Storage files"
log "     📁 system/                       - Legacy uploads"
log "     📁 files/                        - Public files"
echo ""
log "${YELLOW}Test Files Created:${NC}"
log "  • production/backups/${ENV_NAME}/loomio-gdrive-test-$$.txt"
log "  • Upload/storage/loomio-gdrive-test-$$.txt"
echo ""
log "${GREEN}Next Steps:${NC}"
log "  1. Check Google Drive to verify folders exist"
log "  2. Run: make backup (to test database backup)"
log "  3. Run: make sync-files (to test file upload sync)"
echo ""
