#!/bin/bash
set -euo pipefail

# Daily Error Report - Sends exceptions and errors from Loomio logs via email

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

# Load environment variables
if [ -f .env ]; then
    set -a
    source .env
    set +a
else
    echo "Error: .env file not found"
    exit 1
fi

# Email recipient
RECIPIENT="${ALERT_EMAIL}"
if [ -z "$RECIPIENT" ]; then
    echo "Error: ALERT_EMAIL not set in .env"
    exit 1
fi

SUBJECT="Loomio Error Report - $(date +%Y-%m-%d)"
REPORT_FILE="/tmp/loomio-error-report-$(date +%Y%m%d).txt"

# Temporary file for email body
EMAIL_BODY="/tmp/loomio-error-email-body.txt"

# Containers to monitor
CONTAINERS="app worker channels hocuspocus backup"

echo "Generating error report for the last 24 hours..."

# Generate report header
cat > "$REPORT_FILE" << EOF
========================================
Loomio Error Report
Date: $(date +"%Y-%m-%d %H:%M:%S")
Period: Last 24 hours
========================================

EOF

# Extract errors from each container
TOTAL_ERRORS=0

for container in $CONTAINERS; do
    echo "Checking loomio-$container..." >&2

    # Get logs and filter for errors
    ERROR_LOG=$(docker compose logs --since 24h "$container" 2>/dev/null | \
        grep -iE "(ERROR|FATAL|Exception|Traceback|failed|failure)" | \
        grep -viE "(check_updates|netdata|watchtower)" || true)

    if [ -n "$ERROR_LOG" ]; then
        ERROR_COUNT=$(echo "$ERROR_LOG" | wc -l)
        TOTAL_ERRORS=$((TOTAL_ERRORS + ERROR_COUNT))

        echo "" >> "$REPORT_FILE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$REPORT_FILE"
        echo "Container: loomio-$container" >> "$REPORT_FILE"
        echo "Errors found: $ERROR_COUNT" >> "$REPORT_FILE"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        echo "$ERROR_LOG" >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
done

# Add summary at the top
if [ $TOTAL_ERRORS -eq 0 ]; then
    echo "No errors found in the last 24 hours. Skipping email."
    rm -f "$REPORT_FILE"
    exit 0
fi

# Create email with errors
{
    echo "Subject: $SUBJECT - $TOTAL_ERRORS errors found"
    echo "From: ${FROM_EMAIL:-loomio@$CANONICAL_HOST}"
    echo "To: $RECIPIENT"
    echo "Content-Type: text/plain; charset=UTF-8"
    echo ""
    echo "Total errors found: $TOTAL_ERRORS"
    echo ""
    cat "$REPORT_FILE"
} > "$EMAIL_BODY"

echo "Found $TOTAL_ERRORS errors. Sending report..."

# Send email via SMTP using curl
if [ -n "${SMTP_SERVER:-}" ] && [ -n "${SMTP_USERNAME:-}" ] && [ -n "${SMTP_PASSWORD:-}" ]; then
    SMTP_URL="smtp://${SMTP_SERVER}:${SMTP_PORT:-587}"

    curl --url "$SMTP_URL" \
        --ssl-reqd \
        --mail-from "${FROM_EMAIL:-loomio@$CANONICAL_HOST}" \
        --mail-rcpt "$RECIPIENT" \
        --upload-file "$EMAIL_BODY" \
        --user "${SMTP_USERNAME}:${SMTP_PASSWORD}" \
        --silent --show-error

    echo "Error report sent to $RECIPIENT"
else
    echo "Error: SMTP configuration not found in .env"
    cat "$EMAIL_BODY"
    exit 1
fi

# Cleanup
rm -f "$REPORT_FILE" "$EMAIL_BODY"
