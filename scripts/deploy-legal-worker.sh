#!/bin/bash
set -e

# Deploy Cloudflare Worker that serves /impressum and /datenschutz and
# injects a footer link into every Loomio HTML response.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORKER_DIR="$PROJECT_ROOT/cloudflare"
CONFIG_FILE="$WORKER_DIR/wrangler-legal.toml"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=================================================="
echo "Cloudflare Legal Worker Deployment"
echo "=================================================="
echo ""

if ! command -v wrangler &> /dev/null; then
    echo -e "${RED}Error: wrangler CLI is not installed${NC}"
    echo "  Install it with: npm install -g wrangler"
    echo "  Then login:      wrangler login"
    exit 1
fi
echo -e "${GREEN}✓${NC} Wrangler CLI found"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Config not found at $CONFIG_FILE${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Config file found"

if ! wrangler whoami &> /dev/null; then
    echo -e "${YELLOW}Not logged in to Cloudflare — opening browser...${NC}"
    wrangler login
    if ! wrangler whoami &> /dev/null; then
        echo -e "${RED}Error: Login failed${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}✓${NC} Logged in to Cloudflare"

echo ""
echo "Deploying worker (loomio-legal-worker) bound to loomio.lyckbo.de/*..."
( cd "$WORKER_DIR" && wrangler deploy --config "$CONFIG_FILE" )

echo ""
echo -e "${GREEN}=================================================="
echo "Legal Worker Deployed"
echo "==================================================${NC}"
echo ""
echo "Verify:"
echo "  curl -I https://loomio.lyckbo.de/impressum"
echo "  curl -I https://loomio.lyckbo.de/datenschutz"
echo ""
echo "The footer link should appear on every HTML page."
