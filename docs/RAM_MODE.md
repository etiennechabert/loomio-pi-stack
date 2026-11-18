# Production = RAM Mode

## What is RAM Mode?

In production (`RAILS_ENV=production`), Loomio **automatically** runs in RAM mode:
- PostgreSQL database → RAM (tmpfs)
- Redis cache → RAM (tmpfs)
- Backups → RAM (tmpfs) → Google Drive
- **ZERO SD card writes!**

Development (`RAILS_ENV=development`) uses normal disk-based storage.

## Why Use RAM Mode?

**Benefits:**
- **Extended SD card lifespan**: Eliminates constant database writes to SD card
- **Better performance**: RAM is 10-100x faster than SD cards
- **Ideal for Raspberry Pi**: Perfect for systems with 8GB+ RAM
- **Automatic backup/restore**: Smart restore on startup from local backups

**Trade-offs:**
- Data in RAM is lost on power loss or crash (mitigated by hourly backups)
- Requires sufficient RAM (8GB minimum, 16GB recommended)
- Slightly higher risk of data loss between backups

## Requirements

- **RAM**: 8GB minimum, 16GB recommended
- **Disk space**: Enough for database backups in `./data/db_backup/`
- **Backup setup**: Automated backups configured (hourly in RAM mode)
- **Google Drive** (recommended): For disaster recovery

## How It Works

### Architecture

```
┌─────────────────────────────────────────┐
│  System RAM (16GB)                      │
│  ├─ PostgreSQL (tmpfs, no size limit)  │ ← Database stored here
│  ├─ Redis (tmpfs, no size limit)       │ ← Cache stored here
│  └─ Other processes (~8GB)             │
└─────────────────────────────────────────┘
         ↓ Hourly backup
┌─────────────────────────────────────────┐
│  SD Card / Disk                         │
│  └─ ./data/db_backup/                  │ ← Encrypted backups
│     └─ loomio_backup_*.sql.enc         │
└─────────────────────────────────────────┘
         ↓ Sync (optional)
┌─────────────────────────────────────────┐
│  Google Drive                           │
│  └─ Backup/db_backup/                  │ ← Disaster recovery
└─────────────────────────────────────────┘
```

### Startup Process

1. Docker starts with `tmpfs` mounts for `/var/lib/postgresql/data` and Redis `/data`, so the database starts empty
2. The `backup` container (`backup-service/entrypoint.sh`) waits up to 120 seconds for PostgreSQL to accept connections
3. If the database is empty, it looks for the latest backup in `./data/production/backups/` (local first!)
4. If no local backup found, downloads from Google Drive (if configured)
5. Decrypts and restores database to RAM
6. The `backup` container opens the **restore gate** and reports healthy
7. The `app` and `worker` containers, which were waiting for the gate, start Loomio with fully restored data

The restore fails closed. If PostgreSQL never becomes ready, if the `backup` container cannot tell whether the database is empty, or if the restore itself fails, the container exits with an error and is not reported healthy. It never assumes the database is already populated. See [Database restoration fails on startup](#database-restoration-fails-on-startup).

#### The restore gate

The app runs `rake db:prepare` when it starts. On an empty database that creates an empty Loomio schema, after which the `backup` container would see tables and skip the restore. So the app must not start before the restore step is done.

`depends_on` in `docker-compose.yml` only does this for `docker compose up`. When Docker itself starts every container at once (Docker daemon restart, power loss), or on any other start that does not go through `docker compose up`, it is not applied. Instead, the `app` and `worker` containers start through `scripts/wait-for-restore.sh`, which waits until the `backup` container has finished its restore step:

- At the start of each run, `backup-service/entrypoint.sh` closes the gate. When the restore step is done (restored, skipped because the database already had tables, or no backup available) it opens it again by writing one row into the table `loomio_restore_gate` in PostgreSQL's own `postgres` database.
- The gate is in the `postgres` database so that it disappears together with the data (tmpfs) and is never part of a backup (`pg_dump` only dumps the Loomio database). For the same reason `POSTGRES_DB` must not be `postgres`.
- The wait never times out. If the restore fails, Loomio stays down instead of starting on an empty database.

While it waits, the app logs `wait_for_restore: still waiting ...` once a minute (`docker compose logs app`).

### Runtime

- Hourly backups run automatically (configured via cron)
- Each backup is encrypted and stored in `./data/db_backup/`
- Optional Google Drive sync for disaster recovery
- Monitor RAM usage with `make ram-usage`

#### Watchdog and the database

`scripts/watchdog/health-monitor.sh` (run every 5 minutes by `loomio-watchdog.timer`) restarts unhealthy containers, but treats `db` differently because restarting it empties the database:

- **db running but unhealthy:** it is **not** restarted, because that would lose everything written since the last backup. The watchdog logs `CRITICAL: db is unhealthy - NOT restarting it automatically`. If it does not recover by itself, restart it by hand once you accept that loss: `docker compose restart db && docker compose restart backup app worker`.
- **db not running:** its data is already gone, so the watchdog starts it and then restarts `backup` (restores the newest backup), `app` and `worker` (they wait until the restore is done).
- **db emptied behind everyone's back** (for example Docker restarted it after a crash): when the `backup` container says its restore is done but the restore gate is gone and the Loomio database has no tables, the watchdog restarts `backup`, `app` and `worker` the same way.

The watchdog logs to `./logs/loomio-watchdog.log` and the journal (`journalctl -u loomio-watchdog`).

### Shutdown

- `make stop` automatically creates backup before stopping
- `make down` creates final backup before removing containers
- `make restart` creates backup, restarts, and restores data

## Enabling RAM Mode (Production Setup)

RAM mode is **automatic** when using production environment:

### Step 1: Use Production Environment

```bash
# Create production .env
make setup-prod-env

# Configure Google Drive (MANDATORY for production)
nano .env
# Set:
#   GDRIVE_ENABLED=true
#   GDRIVE_CREDENTIALS=<your service account JSON>
#   GDRIVE_FOLDER_ID=<your folder ID>
```

### Step 2: Start Production

```bash
make init   # Initialize database
make start  # Automatically uses RAM mode
```

That's it! The system automatically:
- Detects `RAILS_ENV=production`
- Uses `docker-compose.ram.yml` overlay
- Downloads backup from Google Drive → RAM
- Restores database in RAM
- Runs hourly backups: RAM → Google Drive

## Switching Between Modes

### Production → Development

```bash
# Create backup first
make db-backup

# Switch to development
make down
make setup-dev-env  # Creates .env with RAILS_ENV=development
make init
make start  # Uses disk mode
```

### Development → Production

```bash
# Create backup first (if you have data)
make db-backup

# Switch to production
make down
make setup-prod-env  # Creates .env with RAILS_ENV=production
# Edit .env to configure Google Drive
make start  # Uses RAM mode
```

## Monitoring

### Check RAM Usage

```bash
# Quick snapshot
make ram-usage

# Output:
# RAM Usage (Database & Redis):
#
# Database:
# 1.2G    /var/lib/postgresql/data
#
# Redis:
# 45M     /data
#
# System Memory:
#               total        used        free      shared  buff/cache   available
# Mem:           15Gi       8.2Gi       4.1Gi       350Mi       3.5Gi       7.8Gi
```

### Live Monitoring

```bash
# Real-time stats (Ctrl+C to exit)
make ram-stats
```

### Check Backup Age

```bash
make list-backups

# Output shows backup files and timestamps
```

## Troubleshooting

### "No space left on device" errors

**Cause**: Database exceeded 50% of system RAM (default tmpfs limit)

**Solution**: Your database is too large for available RAM. Either:
1. Disable RAM mode and use disk storage
2. Clean up old data to reduce database size
3. Add more RAM to your system

### Database restoration fails on startup

If the restore cannot be completed, the `backup` container exits with an error instead of reporting healthy, and Docker restarts it to try again. `docker compose up` does not start the app while this lasts.

**Check these:**

```bash
# 1. Read why the restore stopped
docker compose logs backup

# 2. Check the container state (healthy / unhealthy / restarting)
docker compose ps backup

# 3. Verify a backup exists and is not tiny
ls -lh ./data/production/backups/

# 4. Check the backup encryption key is set (prints 1, without showing the key)
grep -c '^BACKUP_ENCRYPTION_KEY=.' .env

# 5. View database startup logs
docker compose logs db
```

**What the log messages mean:**

| Message in `docker compose logs backup` | Meaning |
|---|---|
| `Database did not accept connections within 120s` | PostgreSQL did not start in time. Check `docker compose logs db`. |
| `Could not determine whether the database is empty` | The table count query failed. The restore was neither run nor skipped. |
| `Restore failed: could not decrypt ...` | Wrong `BACKUP_ENCRYPTION_KEY`, or the backup file is damaged. |
| `Restore failed: ...` | The restore did not complete, or left the database without tables. |
| `An earlier restore did not finish` | A restore stopped part-way and left some tables behind. The database is not trusted. This is recorded in `./data/production/backups/.restore-in-progress`, which is removed once the database is empty again or a restore succeeds. |
| `Could not close the restore gate` / `Could not open the restore gate` | The `backup` container could not write to the `postgres` database. The app and worker keep waiting. |

**The app or worker keeps logging `wait_for_restore: still waiting`:** the restore gate is not open. Either the `backup` container is failing (see above), or the `db` container was restarted on its own after the `backup` container had finished. That empties the database and closes the gate. If the watchdog timer is installed (`loomio-watchdog.timer`), it notices within 5 minutes and restores the database (see [Watchdog and the database](#watchdog-and-the-database)). Otherwise run `docker compose restart backup app worker`.

**Retry from a clean state:**

```bash
docker compose down
docker compose up -d
```

The database is on tmpfs, so this starts from an empty database and restores the latest backup again. If the latest backup file itself is damaged, move it out of `./data/production/backups/` first so that the next most recent one is used.

If you repaired the database another way (for example with `make restore-backup`) and are sure it is complete, delete `./data/production/backups/.restore-in-progress` so the `backup` container accepts it.

Do not create a backup (`make create-backup`) while the site is empty or only partly restored.

### Backup service not running hourly

```bash
# Check backup service status
docker compose logs backup

# Should show:
# RAM Mode detected - using HOURLY backups

# Verify cron is running
docker compose exec backup crontab -l
```

### RAM usage growing too fast

**Check these:**

```bash
# 1. Database size in RAM
make ram-usage

# 2. Check for large tables
docker compose exec db psql -U loomio -d loomio_production -c "
  SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
  FROM pg_tables
  ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
  LIMIT 10;
"

# 3. Clean up old data (if applicable)
# Example: Delete old events older than 90 days
docker compose exec app bundle exec rails runner "Event.where('created_at < ?', 90.days.ago).delete_all"
```

## Best Practices

### 1. Monitor RAM Regularly

Set up alerts for high RAM usage:

```bash
# Add to crontab for email alerts
0 */4 * * * free -m | awk 'NR==2{printf "Memory Usage: %.2f%%\n", $3*100/$2 }' | \
  awk '{if ($3 > 80) system("echo \"High RAM usage: \" $0 | mail -s \"RAM Alert\" your@email.com")}'
```

### 2. Test Backups Regularly

```bash
# Monthly test: restore to a test database
make db-backup
# Then verify backup file exists and is recent
ls -lh ./data/db_backup/ | head -2
```

### 3. Keep Google Drive Sync Enabled

Even in RAM mode, sync to Google Drive for disaster recovery:

```bash
# In .env:
GDRIVE_ENABLED=true
RAM_MODE=true
```

### 4. Monitor Backup Age

```bash
# Check age of latest backup
make list-backups

# If backup is >2 hours old, investigate:
docker compose logs backup
```

### 5. Plan for Power Loss

- Use UPS (Uninterruptible Power Supply) for your Raspberry Pi
- In case of power loss, you'll lose up to 1 hour of data (between backups)
- Latest backup will restore automatically on next boot

## Performance Comparison

### Disk Mode (SD Card)
- Random read: ~20 MB/s
- Random write: ~10 MB/s
- Write endurance: Limited (SD card wear)

### RAM Mode (tmpfs)
- Random read: ~2000 MB/s (100x faster)
- Random write: ~2000 MB/s (200x faster)
- Write endurance: Unlimited (RAM doesn't wear out)

## Technical Details

### tmpfs Size Limits

When no explicit size is set, tmpfs defaults to **50% of system RAM**:

- 8GB system → 4GB available for tmpfs
- 16GB system → 8GB available for tmpfs

Memory is allocated **dynamically** as data is written, not reserved upfront.

### Backup Encryption

All backups are encrypted using **Fernet (AES-256)**:

```python
# Key derivation
PBKDF2-HMAC-SHA256(password, salt='loomio-backup-salt', iterations=100000)

# Encryption
AES-256-CBC with HMAC authentication
```

### Smart Restore Logic

1. Wait for PostgreSQL (up to 120 seconds). If it never accepts connections → stop with an error
2. Count the tables in the database. If the count cannot be determined → stop with an error (never assume the database is populated)
3. If the database already has tables → skip the restore
4. Otherwise check `./data/production/backups/` for latest `.sql.enc` file
5. If found → decrypt and restore immediately
6. If not found AND Google Drive enabled → download latest backup
7. If no backup anywhere → warn user and start fresh
8. If the restore fails, or the database still has no tables afterwards → stop with an error

"Stop with an error" means the `backup` container exits without reporting healthy; see [Database restoration fails on startup](#database-restoration-fails-on-startup).

This prioritizes **speed** (local) over **network** (Google Drive).

## FAQ

**Q: How do I enable RAM mode?**
A: It's automatic! Use `make setup-prod-env` instead of `make setup-dev-env`. Production = RAM mode.

**Q: Can I use RAM mode in development?**
A: Not recommended. Development automatically uses disk mode for easier local testing without Google Drive.

**Q: What happens if power is lost?**
A: You lose data since the last hourly backup. On restart, the latest backup (up to 1 hour old) is automatically restored from Google Drive.

**Q: Is Google Drive mandatory?**
A: YES, in production/RAM mode. Backups are stored ONLY in RAM + Google Drive (not on SD card).

**Q: Can I use RAM mode with only 4GB RAM?**
A: Not recommended. You need at least 8GB for a small database, 16GB for production.

**Q: Does this affect uploads/files?**
A: No. Only database and backups use RAM. Files in `./data/uploads/` remain on disk.

**Q: How do I know if my database fits in RAM?**
A: Check current size: `docker compose exec db du -sh /var/lib/postgresql/data`
If it's under 4GB and you have 16GB RAM, you're safe.

**Q: What if database grows beyond RAM limit?**
A: Writes will fail. Either switch to development mode (disk) or add more RAM.

**Q: Can I manually trigger a backup?**
A: Yes: `make db-backup`

**Q: Where are backups stored?**
A: **Production (RAM mode)**: RAM + Google Drive only (NO SD card writes)
**Development (Disk mode)**: `./data/db_backup/` on disk + optional Google Drive

**Q: How do I switch from RAM mode to disk mode?**
A: Create backup with `make db-backup`, then `make down`, edit `.env` to set `RAILS_ENV=development`, and `make start`

## Support

For issues or questions:
- Check logs: `docker compose logs`
- View startup logs: `docker compose logs db`
- Monitor RAM: `make ram-usage`
- Test backup: `make db-backup`
- Report issues: GitHub repository

## Related Documentation

- [BACKUP_GUIDE.md](BACKUP_GUIDE.md) - Backup system architecture
- [README.md](../README.md) - General setup guide
- `.env` - Configuration reference
