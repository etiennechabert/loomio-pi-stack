# Backups Directory

This directory will store encrypted database backups.

Backups are created by the backup service container and follow this naming format:
`loomio_backup_YYYYMMDD_HHMMSS.sql.enc`

## Contents

- `*.sql.enc` - Encrypted database backups (AES-256)
- `*.sql` - Unencrypted backups (if encryption disabled)

## Retention

Backups older than BACKUP_RETENTION_DAYS (default: 30) are automatically deleted.

## Security

⚠️ **Important**: Keep this directory secure and backed up!
- Backups contain all your Loomio data
- Encryption key is in `.env` file
- Consider off-site backup (Google Drive)

For restore instructions, see [BACKUP_GUIDE.md](../BACKUP_GUIDE.md)

