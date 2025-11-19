#!/bin/bash
#
# Loomio Hourly Tasks Runner
# This script executes Loomio's hourly maintenance tasks including:
# - Closing expired polls
# - Sending "closing soon" notifications
# - Sending task reminders
# - Routing received emails
# - Daily cleanup tasks (at midnight)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$PROJECT_DIR/.env"
    set +a
fi

# Timestamp for logging
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "[$TIMESTAMP] Starting Loomio hourly tasks..."

# Check if worker container is running
if ! docker compose -f "$PROJECT_DIR/docker-compose.yml" ps worker | grep -q "Up"; then
    echo "[$TIMESTAMP] ERROR: Worker container is not running!"
    exit 1
fi

# Execute the hourly tasks in the worker container
docker compose -f "$PROJECT_DIR/docker-compose.yml" exec -T worker \
    bundle exec rake loomio:hourly_tasks

EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "[$TIMESTAMP] Hourly tasks completed successfully"
else
    echo "[$TIMESTAMP] ERROR: Hourly tasks failed with exit code $EXIT_CODE"
fi

exit "$EXIT_CODE"
