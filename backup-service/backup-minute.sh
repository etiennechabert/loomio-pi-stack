#!/bin/bash
#
# Minute Backup Script (TESTING ONLY)
# Runs every minute (minutes 1-59)
# Retention: 30 minutes
#

set -e

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting minute backup (TESTING)..."

# Create minute backup
python3 /app/backup.py --type minute

# Sync to Google Drive if enabled
if [ "${GDRIVE_ENABLED}" = "true" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Syncing to Google Drive..."
    bash /app/sync-data.sh

    if [ $? -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Minute backup synced to Google Drive"

        # Clean up old backups from Google Drive
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleaning up old backups from Google Drive..."
        python3 /app/cleanup-gdrive.py
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ WARNING: Google Drive sync failed!" >&2
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Google Drive sync disabled"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Minute backup completed"
