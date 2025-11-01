# Loomio Backup & Restore Guide

Complete guide to backing up and restoring your Loomio data.

## Table of Contents
- [Backup Strategy](#backup-strategy)
- [Automated Backups](#automated-backups)
- [Manual Backups](#manual-backups)
- [Google Drive Integration](#google-drive-integration)
- [Restore Procedures](#restore-procedures)
- [Disaster Recovery](#disaster-recovery)

## Backup Strategy

### What Gets Backed Up

The backup service creates complete PostgreSQL database dumps including:
- User accounts and authentication data
- Groups and membership information
- Threads, proposals, and polls
- Comments and votes
- File metadata (actual files stored separately)
- System settings and configuration

### What's NOT Backed Up

The following require separate backup procedures:
- **Uploaded files** - Stored in Docker volume `app-data`
- **Environment configuration** - Your `.env` file
- **Custom plugins** - If any installed

### Backup Retention

Default retention policy (configurable in `.env`):
- **Frequency**: Hourly
- **Retention**: 30 days
- **Encryption**: AES-256 (Fernet)
- **Location**: Local + Optional Google Drive

### Grandfather-Father-Son Rotation

To implement GFS rotation, configure multiple backup schedules:

```bash
# In .env
BACKUP_SCHEDULE=0 * * * *  # Hourly (sons)
BACKUP_RETENTION_DAYS=7    # Keep for 7 days
```

Then add weekly/monthly backups via cron:
```bash
# Weekly backup (fathers) - every Sunday at 2 AM
0 2 * * 0 docker compose exec backup python3 /app/backup.py

# Monthly backup (grandfathers) - 1st of month at 3 AM
0 3 1 * * docker compose exec backup python3 /app/backup.py
```

## Automated Backups

### How It Works

The backup service runs as a Docker container:
1. Connects to PostgreSQL database
2. Creates a SQL dump using `pg_dump`
3. Encrypts the dump with AES-256
4. Stores locally in `/backups` directory
5. Optionally uploads to Google Drive
6. Cleans up old backups based on retention policy

### Configuration

Edit `.env` file:

```bash
# Backup schedule (cron format)
BACKUP_SCHEDULE=0 * * * *  # Every hour at minute 0

# Retention period
BACKUP_RETENTION_DAYS=30

# Encryption key (IMPORTANT: Keep this secret!)
BACKUP_ENCRYPTION_KEY=generate-with-openssl-rand-hex-32

# Google Drive (optional)
GDRIVE_ENABLED=true
GDRIVE_CREDENTIALS=<service-account-json>
GDRIVE_FOLDER_ID=<folder-id>
```

### Verify Automated Backups

```bash
# Check backup service logs
docker compose logs backup

# List backups
ls -lh backups/

# Should see files like:
# loomio_backup_20240115_120000.sql.enc
```

### Backup Schedule Examples

```bash
# Every hour
BACKUP_SCHEDULE=0 * * * *

# Every 6 hours
BACKUP_SCHEDULE=0 */6 * * *

# Daily at 2 AM
BACKUP_SCHEDULE=0 2 * * *

# Twice daily (2 AM and 2 PM)
BACKUP_SCHEDULE=0 2,14 * * *
```

## Manual Backups

### Create Manual Backup

```bash
# Trigger backup service
docker compose exec backup python3 /app/backup.py

# Or use pg_dump directly
docker compose exec db pg_dump -U loomio -d loomio_production > backup.sql
```

### Backup Everything (Nuclear Option)

```bash
#!/bin/bash
# Complete system backup

BACKUP_NAME="loomio_complete_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_NAME"

# 1. Database
docker compose exec db pg_dump -U loomio -d loomio_production > "$BACKUP_NAME/database.sql"

# 2. Environment config
cp .env "$BACKUP_NAME/.env"

# 3. Uploaded files
docker run --rm -v loomio-pi-stack_app-data:/data -v $(pwd):/backup alpine tar czf /backup/$BACKUP_NAME/app-data.tar.gz -C /data .

# 4. Compress everything
tar czf "$BACKUP_NAME.tar.gz" "$BACKUP_NAME"
rm -rf "$BACKUP_NAME"

echo "Complete backup saved to: $BACKUP_NAME.tar.gz"
```

### Backup Before Major Changes

```bash
# Before updates
docker compose exec backup python3 /app/backup.py

# Label the backup
LATEST=$(ls -t backups/loomio_backup_*.sql.enc | head -n1)
cp "$LATEST" "backups/before_update_$(date +%Y%m%d).sql.enc"
```

## Google Drive Integration

### Why Google Drive?

- **Off-site backup**: Protect against local hardware failure
- **Automatic sync**: Backups uploaded without manual intervention
- **Free tier**: 15GB storage included with Google account
- **Versioning**: Google Drive keeps file versions

### Setup Google Drive Sync

#### 1. Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project: "Loomio Backups"
3. Enable Google Drive API

#### 2. Create Service Account

1. Navigate to "IAM & Admin" > "Service Accounts"
2. Click "Create Service Account"
3. Name: "loomio-backup-service"
4. Click "Create and Continue"
5. Skip role assignment
6. Click "Done"

#### 3. Generate Credentials

1. Click on the service account
2. Go to "Keys" tab
3. Click "Add Key" > "Create new key"
4. Choose "JSON"
5. Download the JSON file

#### 4. Share Drive Folder

1. Create a folder in Google Drive: "Loomio Backups"
2. Right-click > "Share"
3. Share with the service account email (from JSON file)
4. Give "Editor" permissions
5. Copy the folder ID from the URL:
   ```
   https://drive.google.com/drive/folders/FOLDER_ID_HERE
   ```

#### 5. Configure .env

```bash
GDRIVE_ENABLED=true
GDRIVE_FOLDER_ID=your-folder-id-here

# Paste entire JSON content (one line, escape quotes)
GDRIVE_CREDENTIALS='{"type":"service_account","project_id":"...","private_key_id":"...","private_key":"...","client_email":"...","client_id":"...","auth_uri":"...","token_uri":"...","auth_provider_x509_cert_url":"...","client_x509_cert_url":"..."}'
```

#### 6. Test Upload

```bash
# Trigger backup with Google Drive upload
docker compose restart backup
docker compose logs -f backup

# Should see: "✓ Uploaded to Google Drive"
```

### Verify Google Drive Backups

1. Open Google Drive
2. Navigate to your backup folder
3. Verify files are being uploaded
4. Check file sizes match local backups

## Restore Procedures

### Restore from Backup

#### Using Restore Script (Recommended)

```bash
# Interactive restore
./scripts/restore-db.sh

# Follow prompts:
# 1. Select backup file
# 2. Confirm restoration (type 'yes')
# 3. Wait for completion
```

#### Manual Restore

```bash
# 1. Choose backup file
BACKUP_FILE="loomio_backup_20240115_120000.sql.enc"

# 2. Decrypt (if encrypted)
python3 - <<EOF
from cryptography.fernet import Fernet
import base64, hashlib

def derive_key(password):
    kdf = hashlib.pbkdf2_hmac('sha256', password.encode(), b'loomio-backup-salt', 100000, dklen=32)
    return base64.urlsafe_b64encode(kdf)

key = derive_key("YOUR_BACKUP_ENCRYPTION_KEY")
fernet = Fernet(key)

with open("backups/$BACKUP_FILE", 'rb') as f:
    encrypted = f.read()

with open("restore.sql", 'wb') as f:
    f.write(fernet.decrypt(encrypted))
EOF

# 3. Stop dependent services
docker compose stop app worker channels hocuspocus

# 4. Drop and recreate database
docker compose exec db psql -U loomio -d postgres -c "DROP DATABASE loomio_production;"
docker compose exec db psql -U loomio -d postgres -c "CREATE DATABASE loomio_production;"

# 5. Restore
cat restore.sql | docker compose exec -T db psql -U loomio -d loomio_production

# 6. Restart services
docker compose up -d

# 7. Clean up
rm restore.sql
```

### Restore Uploaded Files

```bash
# Extract app-data backup
docker run --rm -v loomio-pi-stack_app-data:/data -v $(pwd):/backup alpine tar xzf /backup/app-data.tar.gz -C /data

# Restart app
docker compose restart app worker
```

### Restore from Google Drive

```bash
# 1. Download from Google Drive
# (Use web interface or gdown/rclone)

# 2. Place in backups directory
mv ~/Downloads/loomio_backup_*.sql.enc backups/

# 3. Run restore script
./scripts/restore-db.sh
```

### Verify Restoration

```bash
# Check database size
docker compose exec db psql -U loomio -d loomio_production -c "\l+"

# Count users
docker compose exec db psql -U loomio -d loomio_production -c "SELECT COUNT(*) FROM users;"

# Check latest activity
docker compose exec db psql -U loomio -d loomio_production -c "SELECT created_at FROM events ORDER BY created_at DESC LIMIT 5;"

# Test web interface
curl http://localhost:3000
```

## Disaster Recovery

### Complete System Failure

If your server dies completely:

#### 1. Prepare New Server

```bash
# On new server
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
git clone https://github.com/yourusername/loomio-pi-stack.git
cd loomio-pi-stack
```

#### 2. Restore Configuration

```bash
# Copy your .env file from backup
# Or recreate from .env.example

nano .env
# Fill in all values
```

#### 3. Download Latest Backup

```bash
# From Google Drive or other backup location
# Place in backups/ directory
```

#### 4. Start Fresh Stack

```bash
docker compose up -d
sleep 30
```

#### 5. Restore Database

```bash
./scripts/restore-db.sh
# Select your backup file
```

#### 6. Restore Files (if backed up)

```bash
# Restore app-data volume
docker run --rm -v loomio-pi-stack_app-data:/data -v $(pwd):/backup alpine tar xzf /backup/app-data.tar.gz -C /data
```

#### 7. Verify Everything

```bash
docker compose ps
docker compose logs
curl http://localhost:3000
```

### SD Card Corruption (Raspberry Pi)

#### Recovery Steps

1. **New SD Card**: Flash fresh Raspberry Pi OS
2. **Reinstall Docker**: Follow [QUICKSTART.md](QUICKSTART.md)
3. **Clone Repo**: `git clone ...`
4. **Restore .env**: From backup or recreate
5. **Restore Database**: Using latest backup
6. **Verify**: All services running

#### Prevention

```bash
# Use read-only root filesystem
# See RESTORE_ON_BOOT.md for stateless configuration

# Or use external USB SSD for data
```

## Backup Best Practices

### Do's ✅

- **Test restores regularly** - Monthly dry runs
- **Keep off-site backups** - Google Drive or external location
- **Monitor backup logs** - Check for failures
- **Encrypt backups** - Always use encryption key
- **Document .env** - Keep encrypted copy somewhere safe
- **Version .env changes** - Track configuration history

### Don'ts ❌

- **Don't commit .env to git** - Contains secrets
- **Don't rely on single backup** - Use multiple locations
- **Don't skip testing restores** - Backups are useless if they don't work
- **Don't forget uploaded files** - Database alone isn't complete
- **Don't use weak encryption keys** - Use `openssl rand -hex 32`

## Backup Monitoring

### Check Backup Health

```bash
# Last backup time
ls -lt backups/ | head -n 5

# Backup sizes (should be consistent)
du -h backups/loomio_backup_*.sql.enc | tail -n 10

# Backup service logs
docker compose logs backup | tail -n 50
```

### Set Up Alerts

#### Email on Backup Failure

Add to backup service:

```python
# In backup.py
import smtplib
from email.message import EmailMessage

def send_alert(subject, body):
    msg = EmailMessage()
    msg['Subject'] = subject
    msg['From'] = 'backup@example.com'
    msg['To'] = 'admin@example.com'
    msg.set_content(body)

    with smtplib.SMTP('smtp.example.com', 587) as smtp:
        smtp.starttls()
        smtp.login('user', 'pass')
        smtp.send_message(msg)

# Call on failure
except Exception as e:
    send_alert('Loomio Backup Failed', str(e))
```

#### Netdata Alerts

Monitor backup directory size and modification time.

## Encryption Details

### Algorithm

- **Method**: Fernet (symmetric encryption)
- **Cipher**: AES-128-CBC
- **MAC**: HMAC-SHA256
- **Key Derivation**: PBKDF2-HMAC-SHA256 (100,000 iterations)

### Key Management

```bash
# Generate strong key
openssl rand -hex 32

# Store securely
# - Password manager
# - Encrypted file
# - Hardware security module (enterprise)

# NEVER store unencrypted in:
# - Git repository
# - Public cloud storage
# - Unencrypted file
```

### Decrypt Manually

```python
from cryptography.fernet import Fernet
import base64, hashlib

def derive_key(password):
    kdf = hashlib.pbkdf2_hmac('sha256', password.encode(),
                               b'loomio-backup-salt', 100000, dklen=32)
    return base64.urlsafe_b64encode(kdf)

key = derive_key("YOUR_BACKUP_ENCRYPTION_KEY")
fernet = Fernet(key)

with open("backup.sql.enc", 'rb') as f:
    encrypted_data = f.read()

decrypted_data = fernet.decrypt(encrypted_data)

with open("backup.sql", 'wb') as f:
    f.write(decrypted_data)
```

## Troubleshooting

### Backup Service Not Running

```bash
# Check status
docker compose ps backup

# View logs
docker compose logs backup

# Restart
docker compose restart backup
```

### Backup Files Too Large

```bash
# Compress backups
gzip backups/*.sql

# Or configure compression in pg_dump
# Edit backup.py, change -F p to -F c
```

### Restore Fails with "Database in Use"

```bash
# Force disconnect all users
docker compose stop app worker channels hocuspocus

# Then retry restore
./scripts/restore-db.sh
```

### Google Drive Upload Fails

```bash
# Check credentials
echo $GDRIVE_CREDENTIALS | jq .

# Verify folder permissions
# Folder must be shared with service account email

# Check service account email
echo $GDRIVE_CREDENTIALS | jq -r .client_email
```

---

**Remember**: Backups are only useful if you test restores regularly! 🔄
