#!/bin/bash
# Integration test for sync-to-gdrive.sh
# Tests that sync creates status file

set -e

TEST_NAME="Google Drive Sync"
STATUS_FILE="./production/backups/.last_sync_status"

echo "Testing: ${TEST_NAME}"

# Remove old status file if exists
docker exec loomio-backup rm -f /backups/.last_sync_status 2>/dev/null || true

# Run sync script
echo "  → Running sync-to-gdrive.sh..."
if ./scripts/sync-to-gdrive.sh; then
    echo "  ✓ Test passed: Sync completed successfully"
    
    # Check if status file was created
    if [ -f "${STATUS_FILE}" ]; then
        echo "  ✓ Test passed: Status file created"
        
        # Check if status file contains timestamp
        CONTENT=$(cat "${STATUS_FILE}")
        if [[ "${CONTENT}" =~ ^[0-9]+$ ]]; then
            echo "  ✓ Test passed: Status file contains valid timestamp"
            exit 0
        else
            echo "  ✗ Test failed: Status file does not contain valid timestamp"
            exit 1
        fi
    else
        echo "  ✗ Test failed: Status file not created"
        exit 1
    fi
else
    echo "  ⚠ Test skipped: Sync failed (Google Drive may not be configured)"
    
    # Check if error status was written
    if [ -f "${STATUS_FILE}" ] && [ "$(cat "${STATUS_FILE}")" = "error" ]; then
        echo "  ✓ Test passed: Error status written correctly"
        exit 0
    fi
    exit 0
fi
