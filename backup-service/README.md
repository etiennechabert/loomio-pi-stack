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
Refuse to continue if the database has no tables or no users (backup.py)
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

Every time the container starts, `entrypoint.sh`:
1. Waits up to 120 seconds for PostgreSQL to accept connections
2. Restores the latest database backup if the database is empty (no tables in the `public` schema)
3. Syncs uploads from Google Drive
4. Marks restore complete by creating `/tmp/.restore-complete` (the container healthcheck, which the app waits for on `docker compose up`)

The restore step fails closed. The container exits with an error, is restarted by Docker to try again, and is **not** reported healthy when:
- PostgreSQL does not accept connections within the timeout
- it cannot tell whether the database is empty (the table count query fails or returns no number)
- the backup cannot be decrypted, the restore fails, or the database still has no tables afterwards
- an earlier restore did not finish and the database is not empty (recorded in `/backups/.restore-in-progress`, which survives the container being recreated)

It never assumes the database is already populated. Read the reason with `make logs SERVICE=backup`, and see [RAM_MODE.md](../docs/RAM_MODE.md#database-restoration-fails-on-startup) for how to retry.

If there is no backup at all (fresh install), the database is left empty and the container still becomes healthy.

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

### Backup refuses to run ("Database has no tables" / "Database has tables but no users")
`backup.py` exits with an error instead of writing a dump when the `public` schema has no tables, or when it has tables but the `users` table has no users other than bots. The second case is what the app leaves behind when it creates an empty schema after a restore was skipped. A dump of an empty database would become the newest backup and be restored on the next start. Find out why the database is empty (`make logs SERVICE=backup`, `make logs SERVICE=db`) before creating any backup. Dumps smaller than 1 MB are discarded for the same reason.

On a fresh install, backups are refused until the first user (usually the admin, `make create-admin`) exists.

If either count cannot be read (for example the query fails), `backup.py` logs a warning and backs up anyway, so a problem in these checks cannot stop backups on its own.

### Google Drive sync failing
```bash
# Test rclone manually
docker exec -it loomio-backup bash
rclone lsf gdrive:production/backups --config /tmp/test.conf
```

### Manual backup fails
- Ensure containers are running: `make status`
- Check backup service health: `docker ps --filter name=loomio-backup`
