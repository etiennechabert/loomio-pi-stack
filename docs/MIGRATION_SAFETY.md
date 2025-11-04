# Database Migration Safety System

## Overview

When updating Loomio or restoring backups, database migrations automatically run to update the schema. If migrations fail, the system has safety mechanisms to prevent data loss and allow recovery.

## Safety Mechanisms

### 1. Pre-Migration Backups

Before running any database migration, the system automatically creates a **pre-migration backup** with a timestamp:
- **Filename format**: `pre-migration-YYYYMMDD-HHMMSS.sql`
- **Location (production/RAM mode)**: `/backups` (in RAM, also synced to Google Drive)
- **Location (development/disk mode)**: `./data/db_backup/`

### 2. Automatic Rollback on Failure

If database migrations fail, the system automatically:
1. Attempts to restore the pre-migration backup
2. Exits with error status
3. Provides clear recovery instructions

## What Happens on Migration Failure

### Scenario 1: `make init` or RAM mode startup (`make start`)

**Failure Flow:**
1. ✅ Database restored from Google Drive backup
2. ✅ Pre-migration backup created
3. ❌ Migrations fail
4. ✅ **Automatic rollback**: Pre-migration backup restored
5. ❌ System exits with error

**Result:** Database is in pre-migration state (restored backup without schema updates)

**Recovery:**
- Check migration error logs: `docker compose logs app`
- Fix migration issues or rollback app version
- Try again: `make start`

### Scenario 2: `make update` (container updates)

**Failure Flow:**
1. ✅ Pre-migration backup created (current state)
2. ✅ New container images pulled
3. ✅ Containers restarted with new code
4. ❌ Migrations fail
5. ❌ **Manual rollback required**

**Result:**
- New images are running
- Database is in old schema state
- Services may be non-functional due to schema mismatch

**Recovery Options:**

#### Option A: Fix and Retry Migrations
```bash
# Check error logs
docker compose logs app

# Fix the issue, then retry
docker compose run --rm app rake db:migrate
```

#### Option B: Rollback to Old Version
```bash
# 1. Restore pre-migration backup
make restore-db
# Select the pre-migration backup

# 2. Edit docker-compose.yml to use old image tags
# Change: image: loomio/loomio:master
# To:     image: loomio/loomio:v2.x.x (your previous version)

# 3. Restart services
docker compose up -d
```

### Scenario 3: `make restore-db` (manual restore)

**Failure Flow:**
1. ✅ Services stopped
2. ✅ Backup restored from Google Drive
3. ✅ Pre-migration backup created
4. ❌ Migrations fail
5. ✅ **Automatic rollback**: Pre-migration backup restored
6. ⚠️  Services remain stopped

**Result:** Database rolled back, services stopped

**Recovery:**
```bash
# Check migration errors
docker compose logs app

# Fix issue, then manually run migrations
docker compose run --rm app rake db:migrate

# If successful, restart services
docker compose start app worker channels hocuspocus
```

## Best Practices

### Before Updates

1. **Create manual backup before major updates:**
   ```bash
   make db-backup
   ```

2. **Test updates in development first:**
   ```bash
   # In dev environment
   docker compose pull
   docker compose up -d
   # Test thoroughly before production update
   ```

### Monitoring Migrations

**Check migration status:**
```bash
docker compose run --rm app rails runner "puts ActiveRecord::Migrator.current_version"
```

**View pending migrations:**
```bash
docker compose run --rm app rake db:migrate:status
```

## Data Loss Prevention

### ✅ Protected Scenarios
- Migration failure → Automatic rollback
- Service crash during migration → Pre-migration backup available
- Schema mismatch → System won't start until resolved

### ⚠️ Potential Data Loss Scenarios

**Scenario:** RAM mode (production) with update failure
- **Risk**: Data created between last regular backup and pre-migration backup
- **Mitigation**: System creates pre-migration backup immediately before migrations
- **Gap**: Only if migration fails AND auto-rollback fails (very rare)

**Recommendation for production:**
- Perform updates during low-activity periods
- Monitor first few migrations closely
- Keep multiple backup generations

## Backup Retention

### Pre-Migration Backups
- Created before every migration attempt
- Named with timestamp for easy identification
- **Recommended**: Keep for 7 days, then clean up manually

### Regular Backups
- Production: Hourly backups to Google Drive
- Development: Manual backups via `make db-backup`

## Emergency Recovery

### Total System Failure

If both migrations and rollback fail:

```bash
# 1. Stop all services
docker compose down

# 2. Check available backups
ls -lh data/db_backup/  # Development
# or check Google Drive  # Production

# 3. Manually restore a known-good backup
docker compose up -d db redis
cat data/db_backup/pre-migration-XXXXXXXX.sql | \
  docker compose exec -T db psql -U loomio -d loomio_production

# 4. Verify database
docker compose run --rm app rails runner "puts User.count"

# 5. If using old backup with new app, manually run migrations
docker compose run --rm app rake db:migrate

# 6. Restart all services
docker compose up -d
```

## Questions & Troubleshooting

### Q: Do I need to manually create backups before updates?
**A:** No, the system automatically creates pre-migration backups. However, manual backups before major updates are still recommended as an extra safety layer.

### Q: What if migrations fail in a loop on every restart?
**A:** The system will auto-restore the pre-migration backup each time. To break the loop:
1. Check logs to understand the migration error
2. Either fix the migration issue or rollback to old app version
3. Don't restart until the issue is resolved

### Q: How do I know if a pre-migration backup was created?
**A:** Check the logs during startup/update. You'll see:
```
✓ Pre-migration backup created: pre-migration-YYYYMMDD-HHMMSS.sql
```

### Q: Should I reboot the Pi if migrations fail?
**A:** **No!** In RAM mode, rebooting will lose all data. The system has already attempted rollback. Instead:
1. Check logs for the actual migration error
2. Fix the issue or rollback app version
3. Only then restart services

## Monitoring Recommendations

### Production Setup

1. **Set up alerts for migration failures:**
   ```bash
   # Check Netdata for container restart alerts
   # Monitor systemd journal: journalctl -u loomio -f
   ```

2. **Regular backup verification:**
   ```bash
   # Weekly: Verify backups can be restored
   make restore-db
   ```

3. **Test migration process in dev environment:**
   ```bash
   # Before production updates, test in dev:
   docker compose pull
   docker compose up -d
   # Verify migrations succeed
   ```

## Summary

The migration safety system provides:
- ✅ Automatic pre-migration backups
- ✅ Automatic rollback on failure
- ✅ Clear error messages and recovery steps
- ✅ Protection against data loss
- ✅ No manual intervention needed for most failures

The system prioritizes **data integrity over availability** - it will fail hard rather than run with mismatched schema.
