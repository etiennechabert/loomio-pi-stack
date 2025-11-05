#!/bin/bash
# Integration test for init-gdrive.sh
# Tests that Google Drive initialization works

set -e

TEST_NAME="Google Drive Initialization"

echo "Testing: ${TEST_NAME}"

# Load environment to check if GDrive is configured
if [ -f .env ]; then
    set -a
    . .env
    set +a
fi

# Check if Google Drive is enabled
if [ "${GDRIVE_ENABLED}" != "true" ]; then
    echo "  ⚠ Test skipped: Google Drive not enabled (set GDRIVE_ENABLED=true in .env)"
    exit 2
fi

# Check if credentials are configured
if [ -z "${GDRIVE_CREDENTIALS}" ] || [ -z "${GDRIVE_FOLDER_ID}" ]; then
    echo "  ⚠ Test skipped: Google Drive credentials not configured"
    exit 2
fi

# Run init-gdrive script
echo "  → Running init-gdrive.sh..."
if ./scripts/init-gdrive.sh > /tmp/init-gdrive-test.log 2>&1; then
    echo "  ✓ Test passed: Init script completed successfully"

    # Check if success message appears in output
    if grep -q "Google Drive Setup Complete" /tmp/init-gdrive-test.log; then
        echo "  ✓ Test passed: Setup completion message found"
    else
        echo "  ✗ Test failed: Setup completion message not found"
        rm -f /tmp/init-gdrive-test.log
        exit 1
    fi

    # Check if folder structure was created
    ENV_NAME="${RAILS_ENV:-production}"
    if grep -q "${ENV_NAME}/backups" /tmp/init-gdrive-test.log; then
        echo "  ✓ Test passed: Folder structure created for ${ENV_NAME}"
    else
        echo "  ✗ Test failed: Folder structure not created"
        rm -f /tmp/init-gdrive-test.log
        exit 1
    fi

    rm -f /tmp/init-gdrive-test.log
    exit 0
else
    echo "  ✗ Test failed: Init script failed"
    cat /tmp/init-gdrive-test.log
    rm -f /tmp/init-gdrive-test.log
    exit 1
fi
