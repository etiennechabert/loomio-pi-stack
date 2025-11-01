#!/bin/bash
#
# Restore Loomio Database on Boot (Stateless Operation)
# This script restores the latest backup on system startup
# Useful for read-only filesystems or stateless deployments
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load environment
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

echo -e "${YELLOW}Loomio: Restore on Boot${NC}"
echo "Finding latest backup..."

# Find latest backup
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/loomio_backup_*.sql* 2>/dev/null | head -n1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "No backups found. Starting with fresh database."
    exit 0
fi

echo "Latest backup: $(basename "$LATEST_BACKUP")"

# Wait for database to be ready
echo "Waiting for database..."
timeout 60 bash -c 'until docker compose exec -T db pg_isready -U "$POSTGRES_USER" > /dev/null 2>&1; do sleep 2; done'

# Restore using restore-db.sh in non-interactive mode
echo "yes" | "$SCRIPT_DIR/restore-db.sh" <<EOF
$(basename "$LATEST_BACKUP")
EOF

echo -e "${GREEN}Restore on boot completed${NC}"
