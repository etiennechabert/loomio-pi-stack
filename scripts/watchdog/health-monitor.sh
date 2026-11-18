#!/bin/bash
#
# Loomio Health Monitoring Script
# Checks service health and restarts if needed. The database is never restarted
# while it runs (see check_db); when it was emptied, it is restored.
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

# Check if a container is healthy. A container without a healthcheck (the
# worker) counts as healthy as long as it runs. Asking for .State.Health.Status
# directly would make docker inspect print an empty line and fail for such a
# container, and the captured "\nnone" would never equal "none", so the worker
# was treated as unhealthy and restarted on every run.
is_healthy() {
    local health
    health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "loomio-$1" 2>/dev/null) || health="unknown"
    [ "$health" = "healthy" ] || [ "$health" = "none" ]
}

# Restart service
restart_service() {
    log "WARNING: $1 is unhealthy, restarting..."
    docker compose restart "$1"
    sleep 10
}

# The database needs special care: by default PostgreSQL keeps its data on tmpfs
# (docker-compose.yml), so a db container that stopped or was restarted - by
# this script, or by Docker itself after a crash - comes back EMPTY. Only the
# backup container restores it, and only when it starts.

# Restore the database after it was emptied ($1: why). The backup container
# restores the newest backup when it starts; the app and worker are restarted so
# that they wait for that restore (scripts/wait-for-restore.sh) instead of
# running against an empty or half-restored database.
restore_database() {
    log "CRITICAL: $1"
    log "CRITICAL: restarting backup (restores the newest backup), app and worker (they wait until the restore is done)"
    docker compose restart backup app worker
    sleep 10
}

# Print the result of SQL $2, run in the db container against database $1
# (empty: the Loomio database)
db_query() {
    # The single-quoted variables are expanded by sh inside the container
    # shellcheck disable=SC2016
    docker exec loomio-db sh -c 'psql -X -U "$POSTGRES_USER" -d "${1:-$POSTGRES_DB}" -tAc "$2"' sh "$1" "$2"
}

# True only when the database was emptied after the backup container restored
# it: the backup container says its restore step is done, yet the restore gate
# (which it opens at the end of that step, in the `postgres` database) is gone
# and the Loomio database has no tables. The backup container deletes
# /tmp/.restore-complete before it starts its restore step and creates it only
# after opening the gate, so this is never true during a restore. Anything that
# cannot be checked counts as false.
database_emptied_after_restore() {
    local gate tables
    docker exec loomio-backup test -f /tmp/.restore-complete 2>/dev/null || return 1
    gate=$(db_query postgres "SELECT to_regclass('public.loomio_restore_gate') IS NOT NULL;" 2>/dev/null) || return 1
    [ "$gate" = "f" ] || return 1
    tables=$(db_query "" "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public';" 2>/dev/null) || return 1
    [ "$tables" = "0" ]
}

# Check the db container. Never restarts a running database: that would delete
# everything written since the last backup.
check_db() {
    if ! is_running db; then
        # In RAM mode its tmpfs is already gone, and with the database on disk
        # the data is still there: either way, starting it loses nothing more
        log "ERROR: db is not running"
        restart_service db
        restore_database "db was not running and starts with an EMPTY database"
        DB_RESTORE_STARTED=true
    elif ! is_healthy db; then
        log "CRITICAL: db is unhealthy - NOT restarting it automatically: in RAM mode (the default) a restart empties the database and loses everything since the last backup"
        log "CRITICAL: if it does not recover by itself, restart it by hand once you accept that loss: docker compose restart db && docker compose restart backup app worker"
    else
        log "OK: db is healthy"
        DB_HEALTHY=true
    fi
}

# Services to monitor
SERVICES=("app" "worker" "db" "redis" "channels" "hocuspocus")
DB_HEALTHY=false
DB_RESTORE_STARTED=false

log "Starting health check..."

for service in "${SERVICES[@]}"; do
    if [ "$service" = "db" ]; then
        check_db
    elif ! is_running "$service"; then
        log "ERROR: $service is not running"
        restart_service "$service"
    elif ! is_healthy "$service"; then
        log "WARNING: $service is unhealthy"
        restart_service "$service"
    else
        log "OK: $service is healthy"
    fi
done

# Docker restarts a crashed db container by itself (restart: unless-stopped),
# which empties the database without anything restoring it
if [ "$DB_HEALTHY" = "true" ] && [ "$DB_RESTORE_STARTED" = "false" ] && database_emptied_after_restore; then
    restore_database "the database is empty although the backup container restored it (the db container was restarted since)"
fi

# Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 90 ]; then
    log "CRITICAL: Disk usage is at ${DISK_USAGE}%"
fi

log "Health check completed"
