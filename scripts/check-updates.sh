#!/bin/bash
#
# Check for Docker image updates and send email notification
# This replaces watchtower's automatic updates with notification-only mode
#

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
EMAIL="${ALERT_EMAIL}"
LOCKFILE="/tmp/loomio-update-check.lock"

# Load environment variables
if [ -f "$PROJECT_ROOT/.env.production" ]; then
    set -a
    source "$PROJECT_ROOT/.env.production"
    set +a
fi

# Prevent concurrent runs
if [ -f "$LOCKFILE" ]; then
    echo "Update check already running (lockfile exists)"
    exit 0
fi
trap 'rm -f "$LOCKFILE"' EXIT
touch "$LOCKFILE"

# Function to check if image has updates
check_image_updates() {
    local image=$1
    local container_name=$2

    # Get current image digest
    local current_digest=$(docker inspect "$container_name" 2>/dev/null | jq -r '.[0].Image' || echo "")
    if [ -z "$current_digest" ]; then
        return 1
    fi

    # Pull latest image metadata (without downloading)
    docker pull "$image" >/dev/null 2>&1 || return 1

    # Get latest image digest
    local latest_digest=$(docker inspect "$image" 2>/dev/null | jq -r '.[0].Id' || echo "")

    # Compare
    if [ "$current_digest" != "$latest_digest" ] && [ -n "$latest_digest" ]; then
        return 0  # Update available
    else
        return 1  # No update
    fi
}

# Function to get image version info
get_version_info() {
    local image=$1
    docker inspect "$image" 2>/dev/null | jq -r '.[0].RepoTags[0] // "unknown"'
}

# Main update check
echo "Checking for Docker image updates..."
UPDATES_AVAILABLE=()

# List of critical services to monitor (excluding watchtower itself)
SERVICES=(
    "postgres:15-alpine:loomio-db"
    "redis:7-alpine:loomio-redis"
    "wizmoisa/loomio:master:loomio-app"
    "wizmoisa/loomio-channel-server:master:loomio-channels"
    "netdata/netdata:v2.7.3:loomio-netdata"
    "adminer:4.8.1:loomio-adminer"
)

for service in "${SERVICES[@]}"; do
    IFS=':' read -r image tag container_name <<< "$service"
    full_image="${image}:${tag}"

    echo "Checking $full_image ($container_name)..."

    if check_image_updates "$full_image" "$container_name"; then
        current_version=$(get_version_info "$full_image")
        UPDATES_AVAILABLE+=("$container_name: $full_image (new version available)")
        echo "  ✓ Update available for $container_name"
    else
        echo "  - Up to date: $container_name"
    fi
done

# Send email if updates are available
if [ ${#UPDATES_AVAILABLE[@]} -gt 0 ]; then
    echo ""
    echo "Updates available! Sending notification..."

    # Prepare email body
    EMAIL_SUBJECT="Loomio Stack Updates Available"
    EMAIL_BODY=$(cat <<EOF
Docker Image Updates Available for Loomio Stack
================================================

The following containers have updates available:

$(printf '%s\n' "${UPDATES_AVAILABLE[@]}")

Action Required:
----------------
1. Review the changes in the update
2. Create a manual backup: ssh to server and run 'make backup'
3. Update images: make pull-docker-images
4. Restart services: make restart

Server: $(hostname)
Checked at: $(date)

Automatic updates are DISABLED to prevent data loss.
You must manually approve and apply updates.

EOF
)

    # Send email using system mail command (requires mailutils)
    if command -v mail >/dev/null 2>&1; then
        echo "$EMAIL_BODY" | mail -s "$EMAIL_SUBJECT" "$EMAIL"
        echo "Email notification sent to $EMAIL"
    elif command -v sendmail >/dev/null 2>&1; then
        {
            echo "To: $EMAIL"
            echo "Subject: $EMAIL_SUBJECT"
            echo ""
            echo "$EMAIL_BODY"
        } | sendmail "$EMAIL"
        echo "Email notification sent to $EMAIL via sendmail"
    else
        # Fallback: use SMTP configuration from .env if available
        if [ -n "${SMTP_SERVER:-}" ] && [ -n "${SMTP_USERNAME:-}" ]; then
            # Use curl to send via SMTP
            SMTP_URL="smtp://${SMTP_SERVER}:${SMTP_PORT:-587}"
            EMAIL_FROM="${SMTP_USERNAME}"

            echo "Sending via SMTP: $SMTP_URL"

            {
                echo "From: Loomio Update Checker <$EMAIL_FROM>"
                echo "To: $EMAIL"
                echo "Subject: $EMAIL_SUBJECT"
                echo ""
                echo "$EMAIL_BODY"
            } | curl --url "$SMTP_URL" \
                --mail-from "$EMAIL_FROM" \
                --mail-rcpt "$EMAIL" \
                --user "${SMTP_USERNAME}:${SMTP_PASSWORD}" \
                --upload-file - \
                --ssl-reqd 2>/dev/null && echo "Email sent via SMTP" || echo "Failed to send email via SMTP"
        else
            echo "WARNING: No mail system configured. Cannot send email."
            echo "Updates available but notification failed!"
            exit 1
        fi
    fi

    # Log to file
    LOG_FILE="$PROJECT_ROOT/data/production/logs/update-check.log"
    mkdir -p "$(dirname "$LOG_FILE")"
    {
        echo "=== Update Check $(date) ==="
        printf '%s\n' "${UPDATES_AVAILABLE[@]}"
        echo ""
    } >> "$LOG_FILE"

    exit 0
else
    echo ""
    echo "All Docker images are up to date. No action needed."
    exit 0
fi
