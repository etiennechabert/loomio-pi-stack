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

1. Docker starts with `tmpfs` mounts for `/var/lib/postgresql/data` and Redis `/data`
2. `init-ram.sh` script runs automatically
3. Checks for latest backup in `./data/db_backup/` (local first!)
4. If no local backup found, downloads from Google Drive (if configured)
5. Decrypts and restores database to RAM
6. Loomio starts with fully restored data

### Runtime

- Hourly backups run automatically (configured via cron)
- Each backup is encrypted and stored in `./data/db_backup/`
- Optional Google Drive sync for disaster recovery
- Monitor RAM usage with `make ram-usage`

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

**Check these:**

```bash
# 1. Verify backup exists
ls -lh ./data/db_backup/

# 2. Check backup encryption key
grep BACKUP_ENCRYPTION_KEY .env

# 3. View startup logs
docker compose logs db

# 4. Manually test restore
./scripts/init-ram.sh
```

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

1. Check `./data/db_backup/` for latest `.sql.enc` file
2. If found → decrypt and restore immediately
3. If not found AND Google Drive enabled → download latest backup
4. If no backup anywhere → warn user and start fresh

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
- `.env.production` - Configuration reference
