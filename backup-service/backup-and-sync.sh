#!/bin/bash
#
# Backup and Sync Wrapper
# Creates database backup and syncs all data to Google Drive
#

set -e

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting backup and sync..."

# Create database backup
python3 /app/backup.py

# Sync to Google Drive if enabled
if [ "${GDRIVE_ENABLED}" = "true" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Syncing data to Google Drive..."
    bash /app/sync-data.sh
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Google Drive sync disabled (GDRIVE_ENABLED != true)"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup and sync completed"
