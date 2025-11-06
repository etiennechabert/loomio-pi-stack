#!/bin/bash
# Integration test for backup-db.sh
# Tests that backup script creates encrypted backup file

set -e

TEST_NAME="Backup Database"
BACKUP_DIR="./data/production/backups"

echo "Testing: ${TEST_NAME}"

# Count existing backups
BEFORE_COUNT=$(ls -1 "${BACKUP_DIR}"/*.sql.enc 2>/dev/null | wc -l)

# Run backup script
echo "  → Running backup-db.sh..."
./scripts/backup-db.sh

# Check if new backup was created
AFTER_COUNT=$(ls -1 "${BACKUP_DIR}"/*.sql.enc 2>/dev/null | wc -l)

if [ "${AFTER_COUNT}" -gt "${BEFORE_COUNT}" ]; then
    echo "  ✓ Test passed: New backup file created"
    
    # Verify file is encrypted (not plain SQL)
    LATEST_BACKUP=$(ls -t "${BACKUP_DIR}"/*.sql.enc | head -1)
    if ! head -1 "${LATEST_BACKUP}" | grep -q "CREATE"; then
        echo "  ✓ Test passed: Backup is encrypted"
        exit 0
    else
        echo "  ✗ Test failed: Backup is not encrypted!"
        exit 1
    fi
else
    echo "  ✗ Test failed: No new backup created"
    exit 1
fi
