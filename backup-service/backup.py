#!/usr/bin/env python3
"""
Loomio Backup Service
Automated PostgreSQL database backups with encryption and Google Drive upload
"""

import os
import sys
import subprocess
import json
from datetime import datetime, timedelta
from pathlib import Path
from cryptography.fernet import Fernet
import base64
import hashlib

# Configuration from environment variables
DB_HOST = os.getenv('DB_HOST', 'db')
DB_PORT = os.getenv('DB_PORT', '5432')
DB_NAME = os.getenv('DB_NAME', 'loomio_production')
DB_USER = os.getenv('DB_USER', 'loomio')
DB_PASSWORD = os.getenv('DB_PASSWORD')
BACKUP_DIR = Path('/backups')
BACKUP_ENCRYPTION_KEY = os.getenv('BACKUP_ENCRYPTION_KEY')
BACKUP_RETENTION_DAYS = int(os.getenv('BACKUP_RETENTION_DAYS', '30'))
GDRIVE_ENABLED = os.getenv('GDRIVE_ENABLED', 'false').lower() == 'true'
GDRIVE_TOKEN = os.getenv('GDRIVE_TOKEN')
GDRIVE_FOLDER_ID = os.getenv('GDRIVE_FOLDER_ID')
RAILS_ENV = os.getenv('RAILS_ENV', 'production')


def log(message):
    """Print timestamped log message"""
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"[{timestamp}] {message}", flush=True)


def derive_fernet_key(password):
    """Derive a Fernet-compatible key from password"""
    kdf_output = hashlib.pbkdf2_hmac('sha256', password.encode(), b'loomio-backup-salt', 100000, dklen=32)
    return base64.urlsafe_b64encode(kdf_output)


def encrypt_file(input_path, output_path, encryption_key):
    """Encrypt a file using Fernet (AES-256)"""
    try:
        fernet_key = derive_fernet_key(encryption_key)
        fernet = Fernet(fernet_key)

        with open(input_path, 'rb') as f:
            data = f.read()

        encrypted_data = fernet.encrypt(data)

        with open(output_path, 'wb') as f:
            f.write(encrypted_data)

        log(f"✓ Encrypted: {output_path.name}")
        return True
    except Exception as e:
        log(f"✗ Encryption failed: {e}")
        return False


def create_database_backup():
    """Create PostgreSQL database dump"""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_filename = f"loomio_backup_{timestamp}.sql"
    backup_path = BACKUP_DIR / backup_filename

    log(f"Starting database backup: {DB_NAME}")

    # Ensure backup directory exists
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)

    # Set PGPASSWORD environment variable for pg_dump
    env = os.environ.copy()
    env['PGPASSWORD'] = DB_PASSWORD

    # Run pg_dump
    cmd = [
        'pg_dump',
        '-h', DB_HOST,
        '-p', DB_PORT,
        '-U', DB_USER,
        '-d', DB_NAME,
        '-F', 'p',  # Plain text format
        '--no-owner',
        '--no-acl',
        '-f', str(backup_path)
    ]

    try:
        result = subprocess.run(cmd, env=env, capture_output=True, text=True, check=True)

        # Check if file was created and has content
        if backup_path.exists() and backup_path.stat().st_size > 0:
            size_mb = backup_path.stat().st_size / (1024 * 1024)
            log(f"✓ Database backup created: {backup_filename} ({size_mb:.2f} MB)")
            return backup_path
        else:
            log(f"✗ Backup file is empty or not created")
            return None

    except subprocess.CalledProcessError as e:
        log(f"✗ Database backup failed: {e.stderr}")
        return None


def encrypt_backup(backup_path):
    """Encrypt the backup file if encryption key is provided"""
    if not BACKUP_ENCRYPTION_KEY:
        log("⚠ Skipping encryption (no encryption key provided)")
        return backup_path

    encrypted_path = backup_path.with_suffix('.sql.enc')

    if encrypt_file(backup_path, encrypted_path, BACKUP_ENCRYPTION_KEY):
        # Remove unencrypted backup
        backup_path.unlink()
        return encrypted_path
    else:
        return backup_path


def upload_to_gdrive(file_path):
    """Upload backup to Google Drive using rclone with OAuth2"""
    if not GDRIVE_ENABLED:
        return True

    if not GDRIVE_TOKEN or not GDRIVE_FOLDER_ID:
        log("⚠ Google Drive upload skipped (token or folder ID missing)")
        return True

    try:
        log("Uploading to Google Drive via rclone...")

        # Create temporary rclone config
        import tempfile
        config_dir = tempfile.mkdtemp(prefix='rclone-')
        config_file = os.path.join(config_dir, 'rclone.conf')

        # Write rclone config with OAuth2 token
        with open(config_file, 'w') as f:
            f.write(f"""[gdrive]
type = drive
scope = drive
token = {GDRIVE_TOKEN}
root_folder_id = {GDRIVE_FOLDER_ID}
""")

        # Upload file using rclone
        # Destination: gdrive:{environment}/backups/<filename>
        dest_path = f"gdrive:{RAILS_ENV}/backups/{file_path.name}"

        result = subprocess.run([
            'rclone', 'copyto',
            str(file_path),
            dest_path,
            '--config', config_file,
            '--progress'
        ], capture_output=True, text=True, timeout=600)

        # Clean up config
        os.unlink(config_file)
        os.rmdir(config_dir)

        if result.returncode == 0:
            log(f"✓ Uploaded to Google Drive: {RAILS_ENV}/backups/{file_path.name}")
            return True
        else:
            log(f"✗ Google Drive upload failed: {result.stderr}")
            return False

    except Exception as e:
        log(f"✗ Google Drive upload failed: {e}")
        return False


def cleanup_old_backups():
    """Remove backups older than retention period"""
    if BACKUP_RETENTION_DAYS <= 0:
        return

    cutoff_date = datetime.now() - timedelta(days=BACKUP_RETENTION_DAYS)
    deleted_count = 0

    for backup_file in BACKUP_DIR.glob('loomio_backup_*.sql*'):
        if backup_file.stat().st_mtime < cutoff_date.timestamp():
            backup_file.unlink()
            deleted_count += 1
            log(f"Deleted old backup: {backup_file.name}")

    if deleted_count > 0:
        log(f"✓ Cleaned up {deleted_count} old backup(s)")


def main():
    """Main backup workflow"""
    log("=" * 60)
    log("Loomio Backup Process Started")
    log("=" * 60)

    # Validate configuration
    if not DB_PASSWORD:
        log("✗ ERROR: DB_PASSWORD not set")
        sys.exit(1)

    # Create database backup
    backup_path = create_database_backup()
    if not backup_path:
        log("✗ Backup process failed")
        sys.exit(1)

    # Encrypt backup
    final_path = encrypt_backup(backup_path)

    # Cleanup old backups
    cleanup_old_backups()

    # Summary
    log("=" * 60)
    log("Backup Process Completed Successfully")
    log(f"Final backup: {final_path.name}")
    log(f"To upload to Google Drive: make upload-to-gdrive")
    log("=" * 60)


if __name__ == '__main__':
    main()
