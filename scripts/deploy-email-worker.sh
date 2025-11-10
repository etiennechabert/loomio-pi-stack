#!/bin/bash
set -e

# Deploy Cloudflare Email Worker for Loomio incoming email support
# This script deploys the email worker and configures secrets

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WORKER_FILE="$PROJECT_ROOT/cloudflare/email-worker.js"
WORKER_NAME="loomio-email-worker"
ENV_FILE="$PROJECT_ROOT/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================================="
echo "Cloudflare Email Worker Deployment"
echo "=================================================="
echo ""

# Check if wrangler is installed
if ! command -v wrangler &> /dev/null; then
    echo -e "${RED}Error: wrangler CLI is not installed${NC}"
    echo ""
    echo "Install it with:"
    echo "  npm install -g wrangler"
    echo ""
    echo "Then login:"
    echo "  wrangler login"
    exit 1
fi

echo -e "${GREEN}✓${NC} Wrangler CLI found"

# Check if worker file exists
if [ ! -f "$WORKER_FILE" ]; then
    echo -e "${RED}Error: Worker file not found at $WORKER_FILE${NC}"
    exit 1
fi

echo -e "${GREEN}✓${NC} Worker file found"

# Check if logged in to Cloudflare, if not prompt to login
if ! wrangler whoami &> /dev/null; then
    echo -e "${YELLOW}Not logged in to Cloudflare${NC}"
    echo ""
    echo "Opening browser for authentication..."
    wrangler login

    # Verify login succeeded
    if ! wrangler whoami &> /dev/null; then
        echo -e "${RED}Error: Login failed${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✓${NC} Logged in to Cloudflare"

# Load environment variables from .env
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    echo -e "${GREEN}✓${NC} Loaded configuration from .env"
else
    echo -e "${RED}Error: .env file not found${NC}"
    echo "  Run 'make init-env' first to create production environment"
    exit 1
fi

# Validate required variables
if [ -z "$EMAIL_PROCESSOR_TOKEN" ]; then
    echo -e "${RED}Error: EMAIL_PROCESSOR_TOKEN is not set in .env${NC}"
    echo ""
    echo "Add to your .env file:"
    echo "  EMAIL_PROCESSOR_TOKEN=\$(openssl rand -hex 32)"
    exit 1
fi

# Check for CANONICAL_HOST to construct webhook URL
if [ -z "$CANONICAL_HOST" ]; then
    echo -e "${RED}Error: CANONICAL_HOST is not set in .env${NC}"
    echo "  CANONICAL_HOST should be your Loomio domain (e.g., loomio.example.com)"
    exit 1
fi

# Construct webhook URL from CANONICAL_HOST - using ActionMailbox relay ingress
WEBHOOK_URL="https://${CANONICAL_HOST}/rails/action_mailbox/relay/inbound_emails"

echo ""
echo "Configuration:"
echo "  Worker Name: $WORKER_NAME"
echo "  Webhook URL: $WEBHOOK_URL"
echo "  Token: ${EMAIL_PROCESSOR_TOKEN:0:8}... (hidden)"
echo ""

# Deploy the worker
echo "Deploying worker..."
wrangler deploy "$WORKER_FILE" \
    --name "$WORKER_NAME" \
    --compatibility-date 2025-01-01

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Worker deployed successfully"
else
    echo -e "${RED}Error: Worker deployment failed${NC}"
    exit 1
fi

echo ""
echo "Configuring secrets..."

# Set WEBHOOK_URL secret
echo "$WEBHOOK_URL" | wrangler secret put WEBHOOK_URL --name "$WORKER_NAME" 2>&1 | grep -v "Enter" || true
echo -e "${GREEN}✓${NC} WEBHOOK_URL configured"

# Set EMAIL_PROCESSOR_TOKEN secret
echo "$EMAIL_PROCESSOR_TOKEN" | wrangler secret put EMAIL_PROCESSOR_TOKEN --name "$WORKER_NAME" 2>&1 | grep -v "Enter" || true
echo -e "${GREEN}✓${NC} EMAIL_PROCESSOR_TOKEN configured"

# Set FALLBACK_EMAIL secret if provided
if [ -n "$FALLBACK_EMAIL" ]; then
    echo "$FALLBACK_EMAIL" | wrangler secret put FALLBACK_EMAIL --name "$WORKER_NAME" 2>&1 | grep -v "Enter" || true
    echo -e "${GREEN}✓${NC} FALLBACK_EMAIL configured"
fi

echo ""
echo -e "${GREEN}=================================================="
echo "Email Worker Deployed Successfully!"
echo "==================================================${NC}"
echo ""
echo -e "${YELLOW}Configuration Summary:${NC}"
echo "  Webhook URL: $WEBHOOK_URL"
echo "  Token: ${EMAIL_PROCESSOR_TOKEN:0:8}... (hidden)"
echo ""
echo "Next steps:"
echo "1. Ensure EMAIL_PROCESSOR_TOKEN is in your Loomio .env file"
echo "2. Add Cloudflare Tunnel route:"
echo "   Path: /rails/action_mailbox/relay/inbound_emails"
echo "   Service: http://app:3000"
echo "3. Restart Loomio: make restart"
echo "4. Enable Email Routing in Cloudflare Dashboard"
echo "5. Create routing rule to send emails to this worker"
echo ""
echo "See INCOMING_EMAIL_SETUP.md for detailed instructions"
echo ""
