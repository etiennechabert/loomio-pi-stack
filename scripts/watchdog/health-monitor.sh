#!/bin/bash
#
# Loomio Health Monitoring Script
# Checks service health and restarts if needed
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "$PROJECT_DIR"

# Logging
mkdir -p logs
LOG_FILE="./logs/loomio-watchdog.log"
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if a container is running
is_running() {
    docker compose ps -q "$1" 2>/dev/null | grep -q .
}

# Check if a container is healthy
is_healthy() {
    local health
    health=$(docker inspect --format='{{.State.Health.Status}}' "loomio-$1" 2>/dev/null || echo "none")
    [ "$health" = "healthy" ] || [ "$health" = "none" ]
}

# Restart service
restart_service() {
    log "WARNING: $1 is unhealthy, restarting..."
    docker compose restart "$1"
    sleep 10
}

# Services to monitor
SERVICES=("app" "worker" "db" "redis" "channels" "hocuspocus")

log "Starting health check..."

for service in "${SERVICES[@]}"; do
    if ! is_running "$service"; then
        log "ERROR: $service is not running"
        restart_service "$service"
    elif ! is_healthy "$service"; then
        log "WARNING: $service is unhealthy"
        restart_service "$service"
    else
        log "OK: $service is healthy"
    fi
done

# Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    log "CRITICAL: Disk usage is at ${DISK_USAGE}%"
fi

log "Health check completed"
