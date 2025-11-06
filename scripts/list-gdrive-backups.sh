#!/bin/bash
#
# List backups available on Google Drive
# Shows count and latest backup for each type
#

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

# Check if backup container is running
if ! docker ps --filter name=loomio-backup --filter status=running --format '{{.Names}}' | grep -q loomio-backup; then
    echo -e "${RED}✗ Backup container is not running!${NC}"
    echo "Start containers with: make start"
    exit 1
fi

# Check if Google Drive is configured
GDRIVE_ENABLED=$(docker exec loomio-backup printenv GDRIVE_ENABLED 2>/dev/null || echo "false")

if [ "$GDRIVE_ENABLED" != "true" ]; then
    echo -e "${YELLOW}⚠ Google Drive is not enabled${NC}"
    echo "Configure Google Drive with: make init-gdrive"
    exit 0
fi

echo -e "${BLUE}Fetching backups from Google Drive...${NC}"
echo ""

# Run listing inside backup container with access to rclone config
docker exec loomio-backup bash -c '
set -e

# Create rclone config
RCLONE_CONFIG_DIR="/tmp/rclone-list-$$"
mkdir -p "$RCLONE_CONFIG_DIR"
cat > "$RCLONE_CONFIG_DIR/rclone.conf" << EOF
[gdrive]
type = drive
scope = drive
token = ${GDRIVE_TOKEN}
root_folder_id = ${GDRIVE_FOLDER_ID}
EOF

ENV_NAME="${RAILS_ENV:-production}"

# Get list of backups
BACKUPS=$(rclone lsjson "gdrive:${ENV_NAME}/backups" \
    --config "$RCLONE_CONFIG_DIR/rclone.conf" \
    --files-only 2>/dev/null || echo "[]")

# Cleanup
rm -rf "$RCLONE_CONFIG_DIR"

# Parse and display by type
echo "'"'"'{\047\033[0;34m\047}Google Drive Backups ('"'"'$ENV_NAME'"'"'){\047\033[0m\047}'"'"'
echo "'"'"'======================================'"'"'
echo ""

for TYPE in hourly daily monthly manual; do
    # Filter backups by type
    COUNT=$(echo "$BACKUPS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for b in data if b[\"Name\"].startswith(\"loomio-$TYPE-\"))
print(count)
")

    if [ "$COUNT" -gt 0 ]; then
        # Get latest backup
        LATEST=$(echo "$BACKUPS" | python3 -c "
import sys, json
from datetime import datetime

data = json.load(sys.stdin)
backups = [b for b in data if b[\"Name\"].startswith(\"loomio-$TYPE-\")]

if backups:
    # Sort by modification time (newest first)
    backups.sort(key=lambda x: x[\"ModTime\"], reverse=True)
    latest = backups[0]

    # Parse modification time
    name = latest.get(\"Name\", \"\")
    mod_time_str = latest.get(\"ModTime\", \"\")
    size = latest.get(\"Size\", 0)

    mod_time = datetime.fromisoformat(mod_time_str.replace(\"Z\", \"+00:00\"))
    size_mb = size / (1024 * 1024)

    print(name)
    print(mod_time.strftime('%Y-%m-%d %H:%M:%S UTC'))
    print(f\"{size_mb:.2f}\")
" | {
            read NAME
            read MODTIME
            read SIZE
            echo "'"'"'{\047\033[0;32m\047}$TYPE:{\047\033[0m\047}'"'"'"
            echo "'"'"'  Count:  $COUNT backups'"'"'"
            echo "'"'"'  Latest: $NAME'"'"'"
            echo "'"'"'  Date:   $MODTIME'"'"'"
            echo "'"'"'  Size:   ${SIZE} MB'"'"'"
        })
        echo ""
    fi
done

# Check if no backups found
if [ "$(echo "$BACKUPS" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")" -eq 0 ]; then
    echo "'"'"'{\047\033[0;33m\047}⚠ No backups found on Google Drive{\047\033[0m\047}'"'"'
fi
'

echo ""
echo -e "${BLUE}Local Backups (data/production/backups):${NC}"
echo "========================================"
echo ""

# List local backups by type
for TYPE in hourly daily monthly manual; do
    COUNT=$(ls -1 data/production/backups/loomio-$TYPE-*.sql.enc 2>/dev/null | wc -l | tr -d ' ')

    if [ "$COUNT" -gt 0 ]; then
        LATEST=$(ls -t data/production/backups/loomio-$TYPE-*.sql.enc 2>/dev/null | head -1)
        if [ -n "$LATEST" ]; then
            SIZE=$(du -h "$LATEST" | cut -f1)
            echo -e "${GREEN}$TYPE:${NC}"
            echo "  Count:  $COUNT backups"
            echo "  Latest: $(basename $LATEST)"
            echo "  Size:   $SIZE"
            echo ""
        fi
    fi
done

# Check if no local backups
if [ "$(ls -1 data/production/backups/*.sql.enc 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No local backups found${NC}"
fi
