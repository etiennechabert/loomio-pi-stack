#!/bin/bash
#
# Daily Backup Script
# Runs once per day at 2 AM
# Retention: 30 days (last 30 backups)
#

set -e

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting daily backup..."

# Create daily backup
python3 /app/backup.py --type daily

# Sync to Google Drive if enabled
if [ "${GDRIVE_ENABLED}" = "true" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Syncing to Google Drive..."
    bash /app/sync-data.sh

    if [ $? -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Daily backup synced to Google Drive"

        # Clean up old backups from Google Drive
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleaning up old backups from Google Drive..."
        python3 /app/cleanup-gdrive.py
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ WARNING: Google Drive sync failed!" >&2
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Google Drive sync disabled"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Daily backup completed"
