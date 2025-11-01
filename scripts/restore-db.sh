#!/bin/bash
#
# Database Restore Script for Loomio
# Restores a PostgreSQL backup (encrypted or unencrypted)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
else
    echo -e "${RED}Error: .env file not found${NC}"
    exit 1
fi

echo "╔════════════════════════════════════════════════════════════╗"
echo "║         Loomio Database Restore Utility                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# List available backups
echo -e "${YELLOW}Available backups:${NC}"
echo ""
ls -lh "$BACKUP_DIR"/loomio_backup_*.sql* 2>/dev/null || echo "No backups found"
echo ""

# Prompt for backup file
read -p "Enter backup filename to restore: " BACKUP_FILE

if [ ! -f "$BACKUP_DIR/$BACKUP_FILE" ]; then
    echo -e "${RED}Error: Backup file not found${NC}"
    exit 1
fi

# Check if encrypted
if [[ "$BACKUP_FILE" == *.enc ]]; then
    if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
        echo -e "${RED}Error: Backup is encrypted but BACKUP_ENCRYPTION_KEY not set in .env${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Decrypting backup...${NC}"
    DECRYPTED_FILE="${BACKUP_FILE%.enc}"

    # Decrypt using Python (same method as backup service)
    python3 - <<EOF
import sys
from pathlib import Path
from cryptography.fernet import Fernet
import base64
import hashlib

def derive_fernet_key(password):
    kdf_output = hashlib.pbkdf2_hmac('sha256', password.encode(), b'loomio-backup-salt', 100000, dklen=32)
    return base64.urlsafe_b64encode(kdf_output)

try:
    fernet_key = derive_fernet_key("$BACKUP_ENCRYPTION_KEY")
    fernet = Fernet(fernet_key)

    with open("$BACKUP_DIR/$BACKUP_FILE", 'rb') as f:
        encrypted_data = f.read()

    decrypted_data = fernet.decrypt(encrypted_data)

    with open("$BACKUP_DIR/$DECRYPTED_FILE", 'wb') as f:
        f.write(decrypted_data)

    print("✓ Decryption successful")
except Exception as e:
    print(f"✗ Decryption failed: {e}")
    sys.exit(1)
EOF

    RESTORE_FILE="$BACKUP_DIR/$DECRYPTED_FILE"
else
    RESTORE_FILE="$BACKUP_DIR/$BACKUP_FILE"
fi

# Confirm restore
echo ""
echo -e "${RED}WARNING: This will DROP and recreate the database!${NC}"
echo -e "${RED}All current data will be lost!${NC}"
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Restore cancelled"
    exit 0
fi

echo ""
echo -e "${YELLOW}Starting database restore...${NC}"

# Stop services that depend on the database
echo "Stopping dependent services..."
docker compose stop app worker channels hocuspocus

# Drop and recreate database
echo "Recreating database..."
docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS $POSTGRES_DB;"
docker compose exec -T db psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE $POSTGRES_DB;"

# Restore backup
echo "Restoring backup..."
cat "$RESTORE_FILE" | docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB"

# Clean up decrypted file if it was created
if [[ "$BACKUP_FILE" == *.enc ]]; then
    rm -f "$RESTORE_FILE"
fi

# Restart services
echo "Restarting services..."
docker compose up -d app worker channels hocuspocus

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Database restore completed successfully!                 ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Services are starting up. Check logs with: docker compose logs -f"
