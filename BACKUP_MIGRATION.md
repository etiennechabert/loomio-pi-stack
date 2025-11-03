# Backup System Migration Guide

This guide explains the new unified backup architecture and how to migrate from the old system.

## What Changed?

### Old Architecture ❌
```
./backups/                    # DB backups (scattered)
Docker volumes:
  - app-data                  # Trapped in volumes
  - app-storage              # Hard to access
  - app-files                # Not easily portable
```

**Problems:**
- Scattered locations
- Uploads trapped in Docker volumes
- Separate sync processes
- Complex restore procedures

### New Architecture ✅
```
./data/
├── db_backup/              # All DB backups
│   └── loomio_backup_*.sql.enc
└── uploads/                # All user uploads
    ├── storage/            # ActiveStorage files
    ├── system/             # Avatars, logos
    └── files/              # Document attachments
```

**Benefits:**
- Single unified location
- Easy local access
- Simple backup/restore
- Portable data directory

## Migration Steps

### 1. Move Existing Backups

```bash
# Move DB backups to new location
mkdir -p data/db_backup
mv backups/*.sql* data/db_backup/ 2>/dev/null || true
```

### 2. Export Docker Volume Data (Optional)

If you have existing data in Docker volumes:

```bash
# Stop services
docker compose down

# Export existing volume data
docker run --rm \
  -v lyckbo-loomio_app-storage:/source \
  -v $(pwd)/data/uploads/storage:/dest \
  alpine sh -c "cp -r /source/* /dest/"

docker run --rm \
  -v lyckbo-loomio_app-data:/source \
  -v $(pwd)/data/uploads/system:/dest \
  alpine sh -c "cp -r /source/* /dest/"

docker run --rm \
  -v lyckbo-loomio_app-files:/source \
  -v $(pwd)/data/uploads/files:/dest \
  alpine sh -c "cp -r /source/* /dest/"
```

### 3. Update and Rebuild

```bash
# Pull latest changes
git pull

# Rebuild backup service with new scripts
docker compose build backup

# Start services
docker compose up -d
```

### 4. Verify Migration

```bash
# Check data structure
ls -la data/db_backup/
ls -la data/uploads/

# Create test backup
make db-backup

# Test sync (if Google Drive configured)
make sync-data
```

## New Commands

### Backup Commands

| Command | Description |
|---------|-------------|
| `make db-backup` | Create encrypted DB backup locally |
| `make sync-data` | Sync all data to Google Drive |
| `make list-backups` | List local DB backups |

### Restore Commands

| Command | Description |
|---------|-------------|
| `make restore-db` | Download & restore latest DB from Google Drive |
| `make restore-uploads` | Download & restore all uploads from Google Drive |

### Automation

The backup service cron now runs:
```bash
# Every 6 hours (configurable via BACKUP_SCHEDULE)
make db-backup && make sync-data
```

## Google Drive Structure

After syncing, your Google Drive will have:

```
[GDRIVE_FOLDER_ID]/
└── Backup/
    ├── db_backup/
    │   └── loomio_backup_*.sql.enc
    └── uploads/
        ├── storage/
        ├── system/
        └── files/
```

## Disaster Recovery

To restore on a new machine:

```bash
# 1. Clone repo and setup
git clone <repo>
cd loomio-pi-stack
make setup-prod-env
# Edit .env with your settings

# 2. Initialize database
make init

# 3. Restore from Google Drive
make restore-db        # Restores database
make restore-uploads   # Restores all files

# 4. Start services
make start
```

## Rollback (if needed)

If you need to rollback to the old system:

```bash
git checkout <previous-commit>
docker compose down -v
docker compose up -d
```

## FAQ

**Q: What happens to old `./backups/` directory?**
A: It's safe to delete after migrating files to `./data/db_backup/`

**Q: Can I backup without Google Drive?**
A: Yes! `make db-backup` creates local backups. Sync is optional.

**Q: How do I test the new backup system?**
A: Run `make db-backup` and verify files appear in `./data/db_backup/`

**Q: Will old backups still work?**
A: Yes, `restore-db` script works with any backup in `./data/db_backup/`

## Support

For issues or questions:
- Check logs: `docker compose logs backup`
- Verify `.env` settings
- Report issues on GitHub
