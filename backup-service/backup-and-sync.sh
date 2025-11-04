#!/bin/bash
#
# Backup and Sync Wrapper
# Creates database backup and syncs to Google Drive
#
# In RAM mode: Keeps only latest backup in RAM to save space
#

set -e

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting backup and sync..."

# In production (RAM mode), delete old backups before creating new one (keep only latest in RAM)
if [ "${RAILS_ENV}" = "production" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] RAM Mode: Cleaning old backups from RAM..."
    # Keep only the most recent backup, delete all others
    BACKUP_COUNT=$(ls -1 /backups/loomio_backup_*.sql.enc 2>/dev/null | wc -l)
    if [ "$BACKUP_COUNT" -gt 1 ]; then
        # Keep only latest, delete older ones
        ls -t /backups/loomio_backup_*.sql.enc | tail -n +2 | xargs rm -f
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Removed $((BACKUP_COUNT - 1)) old backup(s) from RAM"
    fi
fi

# Create new database backup
python3 /app/backup.py

# Sync to Google Drive if enabled
if [ "${GDRIVE_ENABLED}" = "true" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Syncing data to Google Drive..."
    bash /app/sync-data.sh

    if [ $? -eq 0 ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Backup successfully synced to Google Drive"
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ WARNING: Google Drive sync failed!" >&2
        if [ "${RAILS_ENV}" = "production" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ CRITICAL: In production (RAM mode) without GDrive sync, data persistence is at risk!" >&2
        fi
    fi
else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: Google Drive sync disabled"
    if [ "${RAILS_ENV}" = "production" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✗ CRITICAL: Production (RAM mode) requires Google Drive for persistence!" >&2
    fi
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup and sync completed"
