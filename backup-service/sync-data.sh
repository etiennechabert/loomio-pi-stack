#!/bin/bash
#
# Unified Data Sync to Google Drive
# Syncs ALL local data (DB backups + user uploads) to Google Drive
# This version runs inside the backup container
#

set -e

# Check required variables
if [ -z "${GDRIVE_CREDENTIALS}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
    echo "ERROR: GDRIVE_CREDENTIALS or GDRIVE_FOLDER_ID not set"
    exit 1
fi

echo "Syncing data to Google Drive..."

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

# Sync database backups
echo "Syncing database backups..."
rclone sync "/backups" "gdrive:Backup/db_backup" \
    --config "$RCLONE_CONFIG_DIR/rclone.conf" \
    --transfers 4 \
    --checkers 8 \
    --fast-list \
    --exclude '.DS_Store' \
    --exclude 'Thumbs.db' \
    --exclude '*.tmp'

# Sync uploads
echo "Syncing user uploads..."
for upload_dir in "/loomio/storage" "/loomio/public/system" "/loomio/public/files"; do
    if [ -d "$upload_dir" ]; then
        folder_name=$(basename "$upload_dir")
        rclone sync "$upload_dir" "gdrive:Backup/uploads/$folder_name" \
            --config "$RCLONE_CONFIG_DIR/rclone.conf" \
            --transfers 4 \
            --checkers 8 \
            --fast-list \
            --exclude '.DS_Store' \
            --exclude 'Thumbs.db' \
            --exclude '*.tmp'
    fi
done

# Cleanup
rm -rf "$RCLONE_CONFIG_DIR"

echo "✓ Data sync completed"
