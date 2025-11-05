#!/bin/bash
# Integration test for container health
# Tests that all expected containers are running

set -e

TEST_NAME="Container Status"

echo "Testing: ${TEST_NAME}"

# Expected containers
CONTAINERS=("loomio-app" "loomio-worker" "loomio-db" "loomio-redis" "loomio-channels" "loomio-hocuspocus" "loomio-backup")

ALL_RUNNING=true

for container in "${CONTAINERS[@]}"; do
    echo "  → Checking ${container}..."
    if docker ps --filter name="${container}" --filter status=running --format '{{.Names}}' | grep -q "^${container}$"; then
        echo "    ✓ ${container} is running"
    else
        echo "    ✗ ${container} is NOT running"
        ALL_RUNNING=false
    fi
done

if ${ALL_RUNNING}; then
    echo "  ✓ Test passed: All containers running"
    exit 0
else
    echo "  ✗ Test failed: Some containers not running"
    exit 1
fi
