# Staging Environment Setup

Production-identical staging environment for testing migrations, updates, and changes before applying to production.

## How It Works

### Storage Architecture
- **RAM Mode**: Identical to production (tmpfs, data lost on restart)
- **Auto-restore**: Restores from Google Drive backup on every boot
- **Separate folder**: `lyckbo-loomio/staging/backups/` and `lyckbo-loomio/staging/uploads/`

### Data Flow
1. Manually copy latest production backup to `lyckbo-loomio/staging/backups/` folder in Google Drive
2. Copy staging template: `cp .env.staging.example .env`
3. Fill in secrets (tokens, passwords)
4. Start services: `make restart`
5. Backup service auto-downloads and restores from staging folder
6. Staging creates ongoing backups to staging folder (not production)

## Initial Setup

**Note**: `.env.staging.example` and `.env.production.example` are pre-configured templates in the repository. All non-secret values are already set. You only need to fill in secrets.

### 1. Set Up Staging Environment
```bash
# Copy staging template
cp .env.staging.example .env

# Fill in secrets
nano .env
```

**Secrets to fill in** (everything else is pre-configured):
- `GDRIVE_TOKEN` - OAuth token from production (same for staging)
- `GDRIVE_FOLDER_ID` - Folder ID from production (same for staging)
- `CLOUDFLARE_TUNNEL_TOKEN` - Your staging tunnel token (different from production)
- `SECRET_KEY_BASE` - Same as production
- `LOOMIO_HMAC_KEY` - Same as production
- `DEVISE_SECRET` - Same as production
- `SECRET_COOKIE_TOKEN` - Same as production
- `BACKUP_ENCRYPTION_KEY` - Same as production
- `POSTGRES_PASSWORD` - Same as production or different
- `SMTP_PASSWORD` - Same as production or different test account
- `RAILS_INBOUND_EMAIL_PASSWORD` - Same as production
- `EMAIL_PROCESSOR_TOKEN` - Same as production
- `TRANSLATE_CREDENTIALS` - Same as production (optional)

### 2. Prepare Staging Backup Folder
Go to Google Drive and navigate to your `lyckbo-loomio` folder. You'll see:
- `production/backups/` - Production backups
- `production/uploads/` - Production files

**Copy latest production backup to staging**:
1. Find latest backup in `production/backups/` (e.g., `backup-2026-02-01_03-00-00.sql.enc`)
2. Create `staging/backups/` folder if it doesn't exist
3. Copy the backup file to `staging/backups/`

### 3. Start Staging
```bash
# Verify configuration
grep "RAILS_ENV" .env  # Should show: staging
grep "IS_RAM_MODE" .env  # Should show: true

# Start services
make restart
```

Staging will:
1. Download backup from `staging/backups/`
2. Restore database automatically
3. Download uploads from `staging/uploads/` (if any)
4. Start creating hourly backups to staging folder

## Usage Workflows

### Testing Migrations
```bash
# 1. Switch to staging
cp .env.staging.example .env
# Fill in secrets
nano .env
make restart

# 2. Run migration in staging
make migrate-db

# 3. Test the application
# ... verify everything works ...

# 4. If successful, apply to production
cp .env.production.example .env
# Fill in secrets (if not already set)
nano .env
make restart
make migrate-db
make create-backup  # Backup before migration
```

### Testing Updates
```bash
# 1. Switch to staging
cp .env.staging.example .env
# Fill in secrets
nano .env
make restart

# 2. Update images
make update-images
make restart

# 3. Test updated version
# ... verify everything works ...

# 4. If successful, apply to production
cp .env.production.example .env
# Fill in secrets (if not already set)
nano .env
make update-images
make restart
```

## Commands

| Command | Description |
|---------|-------------|
| `cp .env.staging.example .env` | Copy staging template to .env |
| `nano .env` | Edit .env to fill in secrets |
| `cp .env.production.example .env` | Copy production template to .env |
| `make restart` | Restart services to apply changes |
| `make logs` | View logs |
| `grep RAILS_ENV .env` | Check current environment |

## Google Drive Folder Structure

After setup, your Google Drive will have:
```
lyckbo-loomio/
├── production/
│   ├── backups/
│   │   ├── backup-2026-02-01_03-00-00.sql.enc
│   │   └── ...
│   └── uploads/
│       ├── storage/
│       ├── system/
│       └── files/
└── staging/
    ├── backups/
    │   ├── backup-2026-02-01_03-00-00.sql.enc  (copied from production)
    │   ├── backup-2026-02-01_12-00-00.sql.enc  (created by staging)
    │   └── ...
    └── uploads/
        ├── storage/
        ├── system/
        └── files/
```

## Safety Features

1. **Separate databases**: `loomio_production` vs `loomio_staging` prevents confusion
2. **Separate Google Drive folders**: Production and staging backups never conflict
3. **Separate Cloudflare tunnel**: Staging uses different tunnel token (staging.loomio.lyckbo.de)
4. **Environment verification**: Check with `grep RAILS_ENV .env` before operations

## Troubleshooting

**Staging won't start - backup not found**
- Ensure you copied a backup to `staging/backups/` in Google Drive
- Check Google Drive credentials in `.env`
- Verify `GDRIVE_ENABLED=true` in `.env`

**Database not restoring**
- Check logs: `docker compose logs backup`
- Verify `BACKUP_ENCRYPTION_KEY` matches production
- Ensure `IS_RAM_MODE=true` in `.env`

**Wrong environment active**
- Check: `grep RAILS_ENV .env`
- If wrong, copy correct template: `cp .env.staging.example .env` or `cp .env.production.example .env`
- Fill in secrets and restart: `make restart`

**Want fresh staging data (not production copy)**
- Start staging without any backup in `staging/backups/` folder
- Database will be empty, create admin user: `make create-admin`

**Cloudflare tunnel not working**
- Verify `CLOUDFLARE_TUNNEL_TOKEN` in `.env` is for staging domain
- Check tunnel is configured for `staging.loomio.lyckbo.de` in Cloudflare dashboard
- Ensure `--profile cloudflare` is used if needed: `docker compose --profile cloudflare up -d`
