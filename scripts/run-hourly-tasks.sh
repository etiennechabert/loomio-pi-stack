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

cd "$PROJECT_DIR"

# Logging
mkdir -p logs
LOG_FILE="./logs/loomio-hourly.log"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "Starting Loomio hourly tasks..."

# Check if worker container is running
if ! docker compose ps worker | grep -q "Up"; then
    log "ERROR: Worker container is not running!"
    exit 1
fi

# Execute the hourly tasks in the worker container
if docker compose exec -T worker bundle exec rake loomio:hourly_tasks; then
    log "Hourly tasks completed successfully"
else
    log "ERROR: Hourly tasks failed"
    exit 1
fi
