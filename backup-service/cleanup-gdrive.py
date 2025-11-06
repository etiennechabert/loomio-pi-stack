#!/usr/bin/env python3
"""
Google Drive Backup Cleanup
Removes old backups from Google Drive based on retention policies:
- Hourly: 48 hours
- Daily: 30 days
- Monthly: 12 months (365 days)
- Manual: Never deleted
"""

import os
import sys
import subprocess
import json
from datetime import datetime, timedelta
from pathlib import Path

# Configuration
GDRIVE_TOKEN = os.getenv('GDRIVE_TOKEN')
GDRIVE_FOLDER_ID = os.getenv('GDRIVE_FOLDER_ID')
RAILS_ENV = os.getenv('RAILS_ENV', 'production')

# Retention rules (in hours for hourly, minutes for minute, days for others)
RETENTION_RULES = {
    'minute': 30,    # 30 minutes (testing only)
    'hourly': 48,    # 48 hours
    'daily': 30,     # 30 days
    'monthly': 365,  # 12 months
    'manual': None   # Never delete
}


def log(message):
    """Print timestamped log message"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] {message}", flush=True)


def get_gdrive_backups(config_file):
    """List all backups in Google Drive"""
    try:
        result = subprocess.run([
            'rclone', 'lsjson',
            f"gdrive:{RAILS_ENV}/backups",
            '--config', config_file,
            '--files-only'
        ], capture_output=True, text=True, check=True)

        backups = json.loads(result.stdout)
        return backups
    except subprocess.CalledProcessError as e:
        log(f"✗ Failed to list Google Drive backups: {e.stderr}")
        return []
    except json.JSONDecodeError:
        log("✗ Failed to parse Google Drive backup list")
        return []


def classify_backup(filename):
    """Classify backup by type based on filename pattern

    Returns:
        tuple: (backup_type, timestamp) or (None, None) if not recognized
    """
    # Parse backup filename
    if filename.startswith('loomio-minute-'):
        # Format: loomio-minute-YYYYMMDD-HHmmss.sql.enc
        try:
            date_str = filename.replace('loomio-minute-', '').replace('.sql.enc', '')
            timestamp = datetime.strptime(date_str, '%Y%m%d-%H%M%S')
            return ('minute', timestamp)
        except ValueError:
            return (None, None)

    elif filename.startswith('loomio-hourly-'):
        # Format: loomio-hourly-YYYYMMDD-HHmmss.sql.enc
        try:
            date_str = filename.replace('loomio-hourly-', '').replace('.sql.enc', '')
            timestamp = datetime.strptime(date_str, '%Y%m%d-%H%M%S')
            return ('hourly', timestamp)
        except ValueError:
            return (None, None)

    elif filename.startswith('loomio-daily-'):
        # Format: loomio-daily-YYYYMMDD.sql.enc
        try:
            date_str = filename.replace('loomio-daily-', '').replace('.sql.enc', '')
            timestamp = datetime.strptime(date_str, '%Y%m%d')
            return ('daily', timestamp)
        except ValueError:
            return (None, None)

    elif filename.startswith('loomio-monthly-'):
        # Format: loomio-monthly-YYYYMM.sql.enc
        try:
            date_str = filename.replace('loomio-monthly-', '').replace('.sql.enc', '')
            timestamp = datetime.strptime(date_str, '%Y%m')
            return ('monthly', timestamp)
        except ValueError:
            return (None, None)

    elif filename.startswith('loomio-manual-'):
        # Manual backups are never deleted
        return ('manual', None)

    else:
        # Unknown format
        return (None, None)


def should_delete_backup(backup_type, backup_time):
    """Check if backup should be deleted based on retention policy

    Args:
        backup_type: One of 'minute', 'hourly', 'daily', 'monthly', 'manual'
        backup_time: datetime object of backup creation time

    Returns:
        bool: True if backup should be deleted
    """
    retention = RETENTION_RULES.get(backup_type)

    # Manual backups are never deleted
    if retention is None:
        return False

    # Calculate cutoff time
    now = datetime.now()
    if backup_type == 'minute':
        cutoff = now - timedelta(minutes=retention)
    elif backup_type == 'hourly':
        cutoff = now - timedelta(hours=retention)
    else:
        cutoff = now - timedelta(days=retention)

    return backup_time < cutoff


def cleanup_gdrive_backups():
    """Clean up old backups from Google Drive"""
    if not GDRIVE_TOKEN or not GDRIVE_FOLDER_ID:
        log("⚠ Google Drive not configured - skipping cleanup")
        return

    log("Starting Google Drive backup cleanup...")

    # Create temporary rclone config
    import tempfile
    config_dir = tempfile.mkdtemp(prefix='rclone-cleanup-')
    config_file = os.path.join(config_dir, 'rclone.conf')

    with open(config_file, 'w') as f:
        f.write(f"""[gdrive]
type = drive
scope = drive
token = {GDRIVE_TOKEN}
root_folder_id = {GDRIVE_FOLDER_ID}
""")

    # Get list of backups
    backups = get_gdrive_backups(config_file)

    if not backups:
        log("No backups found in Google Drive")
        os.unlink(config_file)
        os.rmdir(config_dir)
        return

    # Process each backup
    deleted_count = {'minute': 0, 'hourly': 0, 'daily': 0, 'monthly': 0, 'manual': 0, 'unknown': 0}
    kept_count = {'minute': 0, 'hourly': 0, 'daily': 0, 'monthly': 0, 'manual': 0, 'unknown': 0}

    for backup in backups:
        filename = backup['Name']
        backup_type, backup_time = classify_backup(filename)

        if backup_type is None:
            log(f"⚠ Unknown backup format: {filename}")
            kept_count['unknown'] += 1
            continue

        # Check if should delete
        if backup_type == 'manual':
            log(f"Keeping manual backup: {filename}")
            kept_count['manual'] += 1
        elif should_delete_backup(backup_type, backup_time):
            # Delete from Google Drive
            try:
                subprocess.run([
                    'rclone', 'delete',
                    f"gdrive:{RAILS_ENV}/backups/{filename}",
                    '--config', config_file
                ], check=True, capture_output=True)
                log(f"Deleted old {backup_type} backup: {filename}")
                deleted_count[backup_type] += 1
            except subprocess.CalledProcessError as e:
                log(f"✗ Failed to delete {filename}: {e.stderr}")
        else:
            kept_count[backup_type] += 1

    # Cleanup config
    os.unlink(config_file)
    os.rmdir(config_dir)

    # Summary
    log("=" * 60)
    log("Google Drive Cleanup Summary:")
    for backup_type in ['minute', 'hourly', 'daily', 'monthly', 'manual']:
        if deleted_count[backup_type] > 0 or kept_count[backup_type] > 0:
            log(f"  {backup_type.title()}: Deleted {deleted_count[backup_type]}, Kept {kept_count[backup_type]}")
    log("=" * 60)


if __name__ == '__main__':
    cleanup_gdrive_backups()
