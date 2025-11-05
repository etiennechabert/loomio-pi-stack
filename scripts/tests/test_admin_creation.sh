#!/bin/bash
# Integration test for create_admin.rb
# Tests that admin can be created with password output

set -e

TEST_NAME="Admin Creation"
TEST_EMAIL="test-admin-$(date +%s)@example.com"
TEST_NAME_USER="Test Admin"

echo "Testing: ${TEST_NAME}"

# Run admin creation script
echo "  → Creating admin: ${TEST_EMAIL}..."
OUTPUT=$(docker exec loomio-app bundle exec rails runner /scripts/ruby/create_admin.rb "${TEST_EMAIL}" "${TEST_NAME_USER}" 2>&1)

# Check if output contains email
if echo "${OUTPUT}" | grep -q "${TEST_EMAIL}"; then
    echo "  ✓ Test passed: Admin email in output"
else
    echo "  ✗ Test failed: Admin email not found in output"
    echo "Output: ${OUTPUT}"
    exit 1
fi

# Check if output contains password
if echo "${OUTPUT}" | grep -q "Password:"; then
    echo "  ✓ Test passed: Password printed in output"
else
    echo "  ✗ Test failed: Password not found in output"
    exit 1
fi

# Verify admin exists in database
echo "  → Verifying admin in database..."
if docker exec loomio-db psql -U loomio -d loomio_production -t -c "SELECT email FROM users WHERE email='${TEST_EMAIL}' AND is_admin=true;" | grep -q "${TEST_EMAIL}"; then
    echo "  ✓ Test passed: Admin exists in database"
    
    # Cleanup: Delete test admin
    docker exec loomio-db psql -U loomio -d loomio_production -c "DELETE FROM users WHERE email='${TEST_EMAIL}';" > /dev/null
    echo "  ✓ Cleanup: Test admin deleted"
    exit 0
else
    echo "  ✗ Test failed: Admin not found in database"
    exit 1
fi
