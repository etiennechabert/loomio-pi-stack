#!/bin/bash
# Loomio Pi Stack - Bootstrap Script for Fresh Raspberry Pi
# Installs minimal dependencies (git, docker, make) to run the Makefile
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/etiennechabert/loomio-pi-stack/main/scripts/bootstrap-pi.sh | bash
#   OR
#   wget -qO- https://raw.githubusercontent.com/etiennechabert/loomio-pi-stack/main/scripts/bootstrap-pi.sh | bash
#   OR
#   bash scripts/bootstrap-pi.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Loomio Pi Stack - Bootstrap Script              ║${NC}"
echo -e "${BLUE}╚═══════════════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}✗ Do not run as root (sudo)${NC}"
    echo "Script will ask for sudo when needed"
    exit 1
fi

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo -e "${BLUE}[1/3] System Update${NC}"
sudo apt update && sudo apt upgrade -y
echo -e "${GREEN}✓ System updated${NC}"
echo ""

echo -e "${BLUE}[2/3] Installing Git & Make${NC}"
sudo apt install -y git make
echo -e "${GREEN}✓ Git: $(git --version)${NC}"
echo -e "${GREEN}✓ Make: $(make --version | head -1)${NC}"
echo ""

echo -e "${BLUE}[3/3] Installing Docker${NC}"
if command_exists docker; then
    echo -e "${GREEN}✓ Docker already installed: $(docker --version)${NC}"
else
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker $USER
    echo -e "${GREEN}✓ Docker installed${NC}"
    echo -e "${YELLOW}⚠ Log out and back in for Docker permissions${NC}"
fi
echo ""

echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ Bootstrap Complete                            ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "  1. Log out and back in"
echo "  2. git clone https://github.com/etiennechabert/loomio-pi-stack.git"
echo "  3. cd loomio-pi-stack"
echo "  4. make install    # Installs remaining dependencies"
echo "  5. cp .env.production.example .env"
echo "  6. nano .env       # Fill in your secrets"
echo "  7. make start"
echo ""
