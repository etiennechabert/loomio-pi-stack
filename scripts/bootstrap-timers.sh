#!/bin/bash
set -euo pipefail

# Bootstrap script to install systemd timers if not already installed
# Runs automatically on boot via loomio-bootstrap.service

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "Loomio Bootstrap: Checking systemd timers..."

# Function to check if a timer is installed and enabled
is_timer_installed() {
    local timer_name=$1
    systemctl is-enabled "$timer_name" >/dev/null 2>&1
}

# Function to install hourly tasks timer
install_hourly_tasks() {
    echo "Installing hourly tasks timer..."
    chmod +x scripts/run-hourly-tasks.sh
    sudo cp loomio-hourly.timer /etc/systemd/system/
    sed 's|{{PROJECT_DIR}}|'"$PROJECT_DIR"'|g' loomio-hourly.service | sudo tee /etc/systemd/system/loomio-hourly.service > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable loomio-hourly.timer
    sudo systemctl start loomio-hourly.timer
    echo "✓ Hourly tasks timer installed"
}

# Function to install error report timer
install_error_report() {
    echo "Installing error report timer..."
    chmod +x scripts/send-error-report.sh
    sudo cp loomio-error-report.timer /etc/systemd/system/
    sed 's|{{PROJECT_DIR}}|'"$PROJECT_DIR"'|g' loomio-error-report.service | sudo tee /etc/systemd/system/loomio-error-report.service > /dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable loomio-error-report.timer
    sudo systemctl start loomio-error-report.timer
    echo "✓ Error report timer installed"
}

# Check and install hourly tasks timer
if is_timer_installed "loomio-hourly.timer"; then
    echo "✓ Hourly tasks timer already installed"
else
    install_hourly_tasks
fi

# Check and install error report timer
if is_timer_installed "loomio-error-report.timer"; then
    echo "✓ Error report timer already installed"
else
    install_error_report
fi

echo "Loomio Bootstrap: Complete"
