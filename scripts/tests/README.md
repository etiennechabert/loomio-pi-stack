# Integration Tests

Integration tests for Loomio Pi Stack scripts. These tests verify actual behavior by running the real scripts against running containers.

## Running Tests

### Run all tests
```bash
make test
```

### Run individual tests
```bash
make test-containers    # Test all containers are running
make test-backup        # Test backup creation
make test-admin         # Test admin user creation
make test-sync          # Test Google Drive sync
```

## Test Descriptions

### 
- **Tests**: Container health and status
- **Verifies**: All 7 expected containers are running
- **No side effects**: Read-only check
- **Runtime**: ~5 seconds

### 
- **Tests**: Database backup functionality
- **Verifies**: 
  - Backup file is created in 
  - File is encrypted (not plain SQL)
- **Side effects**: Creates a new backup file
- **Runtime**: ~30 seconds

### 
- **Tests**: Admin user creation via Rails
- **Verifies**:
  - Script outputs email and password
  - Admin exists in database with is_admin=true
- **Side effects**: Creates and deletes test admin
- **Runtime**: ~10 seconds

### 
- **Tests**: Google Drive sync functionality
- **Verifies**:
  - Sync runs (may skip if GDrive not configured)
  - Status file  is created
  - Status file contains valid timestamp or error
- **Side effects**: Uploads backups to Google Drive (if configured)
- **Runtime**: ~60 seconds (or instant if not configured)

## Prerequisites

- Docker containers must be running: \033[0;34mStarting containers...\033[0m
docker compose up -d
- Database must be initialized with data
- For : Google Drive must be configured ([2025-11-05 23:24:04] [0;34m╔═══════════════════════════════════════════════════════════════[0m
[2025-11-05 23:24:04] [0;34m║      Google Drive Initialization & Validation                ║[0m
[2025-11-05 23:24:04] [0;34m╚═══════════════════════════════════════════════════════════════[0m

[2025-11-05 23:24:04] [0;31m✗ Google Drive is not enabled[0m
[2025-11-05 23:24:04] [1;33mSet GDRIVE_ENABLED=true in .env[0m)

## Test Philosophy

These are **integration tests**, not unit tests:
- Test real behavior, not mocked functions
- Run against actual Docker containers
- Verify end-to-end functionality
- May have side effects (create files, database entries)
- Designed to be safe (cleanup after themselves)

## Adding New Tests

1. Create  in this directory
2. Make it executable: 
3. Follow the pattern:
   - Set  variable
   - Echo progress messages
   - Use  for success,  for failure
   - Clean up any test data
4. Add Makefile target (optional)
5. Tests will automatically run via 

## Example Test Structure

```bash
#!/bin/bash
set -e

TEST_NAME=My Feature
echo Testing: ${TEST_NAME}

# Setup
echo  → Setting up test...

# Test
echo  → Running test...
if [[ condition ]]; then
    echo  ✓ Test passed: Description
    exit 0
else
    echo  ✗ Test failed: Description
    exit 1
fi

# Cleanup happens automatically on exit
```
