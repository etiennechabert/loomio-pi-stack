# Integration Tests

Integration tests for Loomio Pi Stack scripts. These tests verify actual behavior by running the real scripts against running containers.

## Running Tests

### Run all tests
```bash
make test
```

## Test Descriptions

### `test-containers.sh`
- **Tests**: Container health and status
- **Verifies**: All 7 expected containers are running
- **No side effects**: Read-only check
- **Runtime**: ~5 seconds

### `test-backup-db.sh`
- **Tests**: Database backup functionality (`backup-db.sh`)
- **Verifies**: 
  - Backup file is created in `production/backups/`
  - File is encrypted (not plain SQL)
- **Side effects**: Creates a new backup file
- **Runtime**: ~30 seconds

### `test-create-admin.sh`
- **Tests**: Admin user creation (`create_admin.rb`)
- **Verifies**:
  - Script outputs email and password
  - Admin exists in database with is_admin=true
- **Side effects**: Creates and deletes test admin
- **Runtime**: ~10 seconds

### `test-sync-to-gdrive.sh`
- **Tests**: Google Drive sync functionality (`sync-to-gdrive.sh`)
- **Verifies**:
  - Sync runs (may skip if GDrive not configured)
  - Status file `.last_sync_status` is created
  - Status file contains valid timestamp or error
- **Side effects**: Uploads backups to Google Drive (if configured)
- **Runtime**: ~60 seconds (or instant if not configured)

### `test-init-gdrive.sh`
- **Tests**: Google Drive initialization (`init-gdrive.sh`)
- **Verifies**:
  - Script loads .env configuration
  - Folder structure is created ({environment}/backups, {environment}/uploads)
  - Test files are uploaded successfully
  - Script completes with success message
- **Side effects**: Creates folders and test files in Google Drive
- **Runtime**: ~60 seconds (skips if GDrive not configured)

## Prerequisites

- Docker containers must be running: `make start`
- Database must be initialized with data
- For `test-sync-to-gdrive` and `test-init-gdrive`: Google Drive must be configured in .env (`GDRIVE_ENABLED=true`, `GDRIVE_CREDENTIALS`, `GDRIVE_FOLDER_ID`)

## Test Philosophy

These are **integration tests**, not unit tests:
- Test real behavior, not mocked functions
- Run against actual Docker containers
- Verify end-to-end functionality
- May have side effects (create files, database entries)
- Designed to be safe (cleanup after themselves)

## Adding New Tests

1. Create `test-[feature].sh` in this directory (use hyphens, not underscores)
2. Make it executable: `chmod +x test-[feature].sh`
3. Follow the pattern:
   - Set `TEST_NAME` variable
   - Echo progress messages
   - Use `exit 0` for success, `exit 1` for failure
   - Clean up any test data
4. Tests will automatically run via `make test`

## Example Test Structure

```bash
#!/bin/bash
set -e

TEST_NAME="My Feature"
echo "Testing: ${TEST_NAME}"

# Setup
echo "  → Setting up test..."

# Test
echo "  → Running test..."
if [[ condition ]]; then
    echo "  ✓ Test passed: Description"
    exit 0
else
    echo "  ✗ Test failed: Description"
    exit 1
fi

# Cleanup happens automatically on exit
```
