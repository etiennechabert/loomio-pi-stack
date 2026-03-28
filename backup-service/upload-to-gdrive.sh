#!/bin/bash
#
# Unified Data Sync to Google Drive
# Syncs ALL local data (DB backups + user uploads) to Google Drive
# This version runs inside the backup container
#

set -e

# Check required variables
if [ -z "${GDRIVE_TOKEN}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
    echo "ERROR: GDRIVE_TOKEN or GDRIVE_FOLDER_ID not set"
    exit 1
fi

# Get environment name
ENV_NAME="${RAILS_ENV:-production}"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log "Syncing data to Google Drive (${ENV_NAME})..."

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

# Sync database backups to {environment}/backups/
log "Syncing database backups to ${ENV_NAME}/backups/..."
rclone copy "/backups" "gdrive:${ENV_NAME}/backups" \
    --config "$RCLONE_CONFIG_DIR/rclone.conf" \
    --transfers 1 \
    --checkers 2 \
    --fast-list \
    --bwlimit 1M \
    --drive-use-trash=true \
    --exclude '.DS_Store' \
    --exclude 'Thumbs.db' \
    --exclude '*.tmp' \
    --exclude '.last_sync_status'

# Sync uploads to {environment}/uploads/
log "Syncing user uploads to ${ENV_NAME}/uploads/..."
for upload_dir in "/loomio/storage" "/loomio/public/system" "/loomio/public/files"; do
    if [ -d "$upload_dir" ]; then
        folder_name=$(basename "$upload_dir")
        rclone sync "$upload_dir" "gdrive:${ENV_NAME}/uploads/$folder_name" \
            --config "$RCLONE_CONFIG_DIR/rclone.conf" \
            --transfers 1 \
            --checkers 2 \
            --fast-list \
            --bwlimit 1M \
            --drive-use-trash=true \
            --exclude '.DS_Store' \
            --exclude 'Thumbs.db' \
            --exclude '*.tmp'
    fi
done

# Cleanup
rm -rf "$RCLONE_CONFIG_DIR"

log "✓ Data sync completed"
