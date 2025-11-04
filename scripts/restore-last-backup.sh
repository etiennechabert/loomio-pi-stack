#!/bin/bash
#
# Restore Last Backup - Shared Utility
# Downloads latest backup from Google Drive (if enabled) and decrypts it
#
# Usage:
#   DECRYPTED_FILE=$(./scripts/restore-last-backup.sh)
#   if [ $? -eq 0 ]; then
#       # Use $DECRYPTED_FILE
#   fi
#
# Environment Variables:
#   RAILS_ENV              - production or development
#   BACKUP_ENCRYPTION_KEY  - Encryption key for backups
#   GDRIVE_ENABLED         - true/false
#   GDRIVE_CREDENTIALS     - Service account JSON
#   GDRIVE_FOLDER_ID       - Google Drive folder ID
#

set -e

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >&2
}

# Load environment
if [ -f .env ]; then
    set -a
    . .env
    set +a
else
    log "${RED}✗ .env file not found!${NC}"
    exit 1
fi

# Check required variables
if [ -z "${BACKUP_ENCRYPTION_KEY}" ]; then
    log "${RED}✗ BACKUP_ENCRYPTION_KEY not set in .env${NC}"
    exit 1
fi

# Determine if we're in RAM mode (production) or disk mode (development)
IS_RAM_MODE=false
if [ "${RAILS_ENV}" = "production" ]; then
    IS_RAM_MODE=true
fi

# Check Google Drive configuration
SHOULD_DOWNLOAD_FROM_GDRIVE=false
if [ "${GDRIVE_ENABLED}" = "true" ] && [ -n "${GDRIVE_TOKEN}" ] && [ -n "${GDRIVE_FOLDER_ID}" ]; then
    SHOULD_DOWNLOAD_FROM_GDRIVE=true
fi

# In RAM mode, Google Drive is mandatory
if [ "$IS_RAM_MODE" = true ] && [ "$SHOULD_DOWNLOAD_FROM_GDRIVE" = false ]; then
    log "${RED}✗ ERROR: Google Drive is MANDATORY in production (RAM mode)!${NC}"
    log "${RED}  Configure GDRIVE_ENABLED, GDRIVE_CREDENTIALS, and GDRIVE_FOLDER_ID${NC}"
    exit 1
fi

# Determine backup location
if [ "$IS_RAM_MODE" = true ]; then
    # RAM mode: backups are in tmpfs inside backup container
    BACKUP_LOCATION="container"
    BACKUP_DIR="/backups"
else
    # Disk mode: backups are on host filesystem
    BACKUP_LOCATION="host"
    BACKUP_DIR="./data/db_backup"
    mkdir -p "$BACKUP_DIR"
fi

# Download from Google Drive if needed and enabled
if [ "$SHOULD_DOWNLOAD_FROM_GDRIVE" = true ]; then
    log "${BLUE}Downloading latest backup from Google Drive...${NC}"

    if [ "$BACKUP_LOCATION" = "container" ]; then
        # RAM mode: Download into backup container's tmpfs
        docker compose exec -T backup bash -c "
            set -e

            # Create rclone config
            RCLONE_CONFIG_DIR=\"/tmp/rclone-config-\$\$\"
            mkdir -p \"\$RCLONE_CONFIG_DIR\"

            cat > \"\$RCLONE_CONFIG_DIR/rclone.conf\" << 'RCLONE_EOF'
[gdrive]
type = drive
scope = drive
token = ${GDRIVE_TOKEN}
root_folder_id = ${GDRIVE_FOLDER_ID}
RCLONE_EOF

            # Download latest backup to tmpfs
            echo 'Downloading from Google Drive...' >&2
            rclone copy 'gdrive:Backup/db_backup' '${BACKUP_DIR}' \
                --config \"\$RCLONE_CONFIG_DIR/rclone.conf\" \
                --max-age 7d \
                --quiet >&2

            rm -rf \"\$RCLONE_CONFIG_DIR\"

            # Check if we got a backup
            BACKUP_COUNT=\$(ls -1 ${BACKUP_DIR}/loomio_backup_*.sql.enc 2>/dev/null | wc -l)
            if [ \$BACKUP_COUNT -eq 0 ]; then
                echo 'ERROR: No backup found in Google Drive' >&2
                exit 1
            fi

            echo 'Download complete!' >&2
        "

        if [ $? -ne 0 ]; then
            log "${RED}✗ Failed to download backup from Google Drive${NC}"
            exit 1
        fi
    else
        # Disk mode: Download to host filesystem
        RCLONE_CONFIG_DIR="/tmp/rclone-config-$$"
        mkdir -p "$RCLONE_CONFIG_DIR"

        cat > "$RCLONE_CONFIG_DIR/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
token = ${GDRIVE_TOKEN}
root_folder_id = ${GDRIVE_FOLDER_ID}
EOF

        rclone sync "gdrive:Backup/db_backup" "$BACKUP_DIR" \
            --config "$RCLONE_CONFIG_DIR/rclone.conf" \
            --quiet

        if [ $? -ne 0 ]; then
            log "${RED}✗ Failed to download from Google Drive${NC}"
            rm -rf "$RCLONE_CONFIG_DIR"
            exit 1
        fi

        rm -rf "$RCLONE_CONFIG_DIR"
        log "${GREEN}✓ Downloaded backups from Google Drive${NC}"
    fi
fi

# Find latest backup
if [ "$BACKUP_LOCATION" = "container" ]; then
    # Get latest backup from container
    LATEST_BACKUP=$(docker compose exec -T backup bash -c "ls -t ${BACKUP_DIR}/loomio_backup_*.sql.enc 2>/dev/null | head -1" | tr -d '\r')
else
    # Get latest backup from host
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/loomio_backup_*.sql.enc 2>/dev/null | head -1)
fi

if [ -z "$LATEST_BACKUP" ]; then
    log "${RED}✗ No backup found${NC}"
    exit 1
fi

log "${GREEN}✓ Found backup: $(basename "$LATEST_BACKUP")${NC}"

# Decrypt backup
log "${BLUE}Decrypting backup...${NC}"

if [ "$BACKUP_LOCATION" = "container" ]; then
    # Decrypt inside container and capture only the file path
    DECRYPTED_FILE=$(docker compose exec -T backup bash -c "
        set -e

        LATEST_BACKUP=\"\$(ls -t ${BACKUP_DIR}/loomio_backup_*.sql.enc 2>/dev/null | head -1)\"

        if [ -z \"\$LATEST_BACKUP\" ]; then
            echo 'ERROR: No backup found' >&2
            exit 1
        fi

        # Decrypt backup in RAM
        DECRYPTED_FILE=\"\${LATEST_BACKUP%.enc}\"

        python3 -c \"
from cryptography.fernet import Fernet
import base64
import hashlib
import sys

def derive_fernet_key(password):
    kdf_output = hashlib.pbkdf2_hmac('sha256', password.encode(), b'loomio-backup-salt', 100000, dklen=32)
    return base64.urlsafe_b64encode(kdf_output)

try:
    fernet_key = derive_fernet_key('${BACKUP_ENCRYPTION_KEY}')
    fernet = Fernet(fernet_key)

    with open('\$LATEST_BACKUP', 'rb') as f:
        encrypted_data = f.read()

    decrypted_data = fernet.decrypt(encrypted_data)

    with open('\$DECRYPTED_FILE', 'wb') as f:
        f.write(decrypted_data)

    print('✓ Decrypted successfully', file=sys.stderr)
except Exception as e:
    print(f'✗ Decryption failed: {e}', file=sys.stderr)
    sys.exit(1)
\" >&2

        # Output ONLY the decrypted file path to stdout
        echo \"\$DECRYPTED_FILE\"
    " | tr -d '\r\n')

    if [ $? -ne 0 ] || [ -z "$DECRYPTED_FILE" ]; then
        log "${RED}✗ Decryption failed${NC}"
        exit 1
    fi
else
    # Decrypt on host
    DECRYPTED_FILE="${LATEST_BACKUP%.enc}"

    python3 -c "
from cryptography.fernet import Fernet
import base64
import hashlib
import sys

def derive_fernet_key(password):
    kdf_output = hashlib.pbkdf2_hmac('sha256', password.encode(), b'loomio-backup-salt', 100000, dklen=32)
    return base64.urlsafe_b64encode(kdf_output)

try:
    fernet_key = derive_fernet_key('${BACKUP_ENCRYPTION_KEY}')
    fernet = Fernet(fernet_key)

    with open('${LATEST_BACKUP}', 'rb') as f:
        encrypted_data = f.read()

    decrypted_data = fernet.decrypt(encrypted_data)

    with open('${DECRYPTED_FILE}', 'wb') as f:
        f.write(decrypted_data)

    print('✓ Backup decrypted successfully')
except Exception as e:
    print(f'✗ Decryption failed: {e}', file=sys.stderr)
    sys.exit(1)
"

    if [ $? -ne 0 ]; then
        log "${RED}✗ Failed to decrypt backup${NC}"
        exit 1
    fi
fi

log "${GREEN}✓ Backup ready: $(basename "$DECRYPTED_FILE")${NC}"

# Output the decrypted file path for the caller
echo "$DECRYPTED_FILE"
