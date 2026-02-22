# Multi-Tier Backup System

This backup service implements a comprehensive multi-tier backup strategy for Loomio with automatic retention management.

## Backup Types

### 1. Hourly Backups
- **Schedule**: Hours 1-23 (`0 1-23 * * *`)
- **Retention**: 24 hours (permanent delete)
- **Format**: `loomio-hourly-YYYYMMDD-HHmmss.sql.enc`
- **Purpose**: Quick recovery from recent issues

### 2. Daily Backups
- **Schedule**: Midnight Sun,Tue-Sat (`0 0 * * 0,2-6`)
- **Retention**: 7 days (30d in GDrive trash)
- **Format**: `loomio-daily-YYYYMMDD.sql.enc`
- **Purpose**: Medium-term recovery

### 3. Weekly Backups
- **Schedule**: Midnight Monday (`0 0 * * 1`)
- **Retention**: 12 weeks / 84 days (30d in GDrive trash)
- **Format**: `loomio-weekly-YYYYMMDD.sql.enc`
- **Purpose**: Long-term archival

### 4. Manual Backups
- **Trigger**: User-initiated via `make create-backup`
- **Retention**: 30 days (30d in GDrive trash)
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
4. **backup-weekly.sh** - Weekly backup wrapper
5. **cleanup-gdrive.py** - Google Drive retention manager
6. **upload-to-gdrive.sh** - Upload to Google Drive
7. **entrypoint.sh** - Cron scheduler setup

### Backup Flow

```
Scheduled Time
     ↓
Run backup script (hourly/daily/weekly)
     ↓
Create database dump (backup.py)
     ↓
Encrypt backup (AES-256)
     ↓
Clean up old local backups (by type)
     ↓
Upload to Google Drive (upload-to-gdrive.sh)
     ↓
Clean up old GDrive backups (cleanup-gdrive.py)
     ↓
Done
```

### Retention Logic

- **Local**: Old backups deleted based on per-type retention rules
- **Google Drive**: Cleaned up after each upload; hourly permanently deleted, all others sent to GDrive trash (~30d recoverable)

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
│   │   ├── loomio-weekly-*.sql.enc
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
