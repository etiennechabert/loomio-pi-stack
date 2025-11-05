#!/bin/bash
# Restart unhealthy containers

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
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

log "${BLUE}Checking container health...${NC}"

RESTARTED=false

for container in "${CONTAINERS[@]}"; do
    if ! is_healthy "$container"; then
        log "${YELLOW}Restarting unhealthy container: $container${NC}"
        docker restart "$container"
        RESTARTED=true
        sleep 5
    fi
done

if $RESTARTED; then
    log "${GREEN}✓ Unhealthy containers restarted${NC}"
    log "Check status with: make health"
else
    log "${GREEN}✓ All containers healthy - no action needed${NC}"
fi
