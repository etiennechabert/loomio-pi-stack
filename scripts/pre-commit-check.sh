#!/bin/bash
#
# Pre-commit Checks for Loomio Stack
# Validates configuration before committing
#

set -e

echo "Running pre-commit checks..."

# Check docker-compose.yml syntax
echo "  ✓ Validating docker-compose.yml..."
docker compose config > /dev/null

# Check .env.example has all required variables
echo "  ✓ Checking .env.example..."
REQUIRED_VARS=(
    "POSTGRES_PASSWORD"
    "SECRET_KEY_BASE"
    "LOOMIO_HMAC_KEY"
    "SMTP_SERVER"
    "CANONICAL_HOST"
)

for var in "${REQUIRED_VARS[@]}"; do
    if ! grep -q "^$var=" .env.example 2>/dev/null; then
        echo "  ✗ Missing required variable in .env.example: $var"
        exit 1
    fi
done

# Check script permissions
echo "  ✓ Checking script permissions..."
find scripts -type f -name "*.sh" -exec chmod +x {} \;

# Check for secrets in tracked files
echo "  ✓ Scanning for potential secrets..."
if git diff --cached --name-only | xargs grep -l -E "(password|secret|token|key).*=.*[a-zA-Z0-9]{20,}" 2>/dev/null; then
    echo "  ⚠ WARNING: Potential secrets detected. Please review."
fi

echo ""
echo "All pre-commit checks passed!"
