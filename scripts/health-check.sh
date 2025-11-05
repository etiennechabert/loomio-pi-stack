#!/bin/bash
# Check container health status
# Returns 0 if all healthy, 1 if any unhealthy

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "$1"
}

# Check if container is healthy
is_healthy() {
    local container="$1"
    local health
    health=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
    
    # If no health check defined, check if running
    if [ "$health" = "none" ]; then
        docker ps --filter name="$container" --filter status=running --format '{{.Names}}' | grep -q "$container"
        return $?
    fi
    
    [ "$health" = "healthy" ]
}

# Services to monitor (container names)
CONTAINERS=("loomio-app" "loomio-worker" "loomio-db" "loomio-redis" "loomio-channels" "loomio-hocuspocus" "loomio-backup")

log "${BLUE}═══════════════════════════════════════════════════${NC}"
log "${BLUE}  Container Health Status${NC}"
log "${BLUE}═══════════════════════════════════════════════════${NC}"

ALL_HEALTHY=true

for container in "${CONTAINERS[@]}"; do
    if is_healthy "$container"; then
        log "${GREEN}✓ $container: healthy${NC}"
    else
        log "${RED}✗ $container: unhealthy${NC}"
        ALL_HEALTHY=false
    fi
done

log "${BLUE}═══════════════════════════════════════════════════${NC}"

if $ALL_HEALTHY; then
    log "${GREEN}All containers healthy!${NC}"
    exit 0
else
    log "${YELLOW}Some containers are unhealthy. Run: make restart-unhealthy${NC}"
    exit 1
fi
