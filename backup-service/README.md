# Multi-Tier Backup System

This backup service implements a comprehensive multi-tier backup strategy for Loomio with automatic retention management.

## Backup Types

### 1. Hourly Backups
- **Schedule**: Every hour (`0 * * * *`)
- **Retention**: 48 hours (last 48 backups)
- **Format**: `loomio-hourly-YYYYMMDD-HHmmss.sql.enc`
- **Purpose**: Quick recovery from recent issues

### 2. Daily Backups
- **Schedule**: 2 AM daily (`0 2 * * *`)
- **Retention**: 30 days
- **Format**: `loomio-daily-YYYYMMDD.sql.enc`
- **Purpose**: Medium-term recovery

### 3. Monthly Backups
- **Schedule**: 1st of month at 3 AM (`0 3 1 * *`)
- **Retention**: 12 months (365 days)
- **Format**: `loomio-monthly-YYYYMM.sql.enc`
- **Purpose**: Long-term archival

### 4. Manual Backups
- **Trigger**: User-initiated via `make create-backup`
- **Retention**: **Never deleted** (permanent)
- **Format**: `loomio-manual-YYYYMMDD-HHmmss-<reason>.sql.enc`
- **Purpose**: Important milestones (updates, migrations, etc.)

## Usage

### Creating Manual Backups

```bash
make create-backup
```

You'll be prompted to enter a reason:
```
Enter backup reason: update-from-v42.0.4
```

This creates: `loomio-manual-20250106-143022-update-from-v42.0.4.sql.enc`

### Viewing Backup Info

```bash
make backup-info
```

### Restoring from Backup

#### From Google Drive (Complete Disaster Recovery)
```bash
make restore-from-gdrive
```

#### From Local Backup
```bash
make restore-backup
```

## Architecture

### Components

1. **backup.py** - Core backup logic with type support
2. **backup-hourly.sh** - Hourly backup wrapper
3. **backup-daily.sh** - Daily backup wrapper
4. **backup-monthly.sh** - Monthly backup wrapper
5. **cleanup-gdrive.py** - Google Drive retention manager
6. **sync-data.sh** - Upload to Google Drive
7. **entrypoint.sh** - Cron scheduler setup

### Backup Flow

```
Scheduled Time
     ↓
Run backup script (hourly/daily/monthly)
     ↓
Create database dump (backup.py)
     ↓
Encrypt backup (AES-256)
     ↓
Clean up old local backups (by type)
     ↓
Sync to Google Drive (sync-data.sh)
     ↓
Clean up old GDrive backups (cleanup-gdrive.py)
     ↓
Done
```

### Retention Logic

- **Local**: Old backups deleted before creating new one (RAM mode)
- **Google Drive**: Cleaned up after each sync
- **Manual backups**: Explicitly excluded from all cleanup

## Configuration

Set in `.env`:

```bash
# Required
DB_PASSWORD=your_password
BACKUP_ENCRYPTION_KEY=your_encryption_key

# Google Drive (optional but recommended)
GDRIVE_ENABLED=true
GDRIVE_TOKEN='{"access_token": "...", ...}'
GDRIVE_FOLDER_ID=your_folder_id
```

## Auto-Restore on Boot

In production (RAM mode), the service automatically:
1. Restores latest database backup
2. Syncs uploads from Google Drive
3. Marks restore complete (for healthcheck)

## Monitoring

View backup logs:
```bash
make logs SERVICE=backup
```

Check backup files:
```bash
ls -lh data/production/backups/
```

## Google Drive Structure

```
GDRIVE_FOLDER_ID/
├── production/
│   ├── backups/
│   │   ├── loomio-hourly-*.sql.enc
│   │   ├── loomio-daily-*.sql.enc
│   │   ├── loomio-monthly-*.sql.enc
│   │   └── loomio-manual-*.sql.enc
│   └── uploads/
│       ├── storage/
│       ├── system/
│       └── files/
```

## Troubleshooting

### Backup not running
```bash
# Check cron is running
docker exec loomio-backup crontab -l

# Check logs
make logs SERVICE=backup
```

### Google Drive sync failing
```bash
# Test rclone manually
docker exec -it loomio-backup bash
rclone lsf gdrive:production/backups --config /tmp/test.conf
```

### Manual backup fails
- Ensure containers are running: `make status`
- Check backup service health: `docker ps --filter name=loomio-backup`
