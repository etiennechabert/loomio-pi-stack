#!/bin/bash
#
# Monthly Backup Script
# Runs on the 1st of each month at 3 AM
# Retention: 12 months (365 days)
#

set -e

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting monthly backup..."

# Create monthly backup
python3 /app/backup.py --type monthly

# Sync to Google Drive if enabled
if [ "${GDRIVE_ENABLED}" = "true" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Syncing to Google Drive..."
    bash /app/sync-data.sh

    if [ $? -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Monthly backup synced to Google Drive"

        # Clean up old backups from Google Drive
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleaning up old backups from Google Drive..."
        python3 /app/cleanup-gdrive.py
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ WARNING: Google Drive sync failed!" >&2
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Google Drive sync disabled"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Monthly backup completed"
