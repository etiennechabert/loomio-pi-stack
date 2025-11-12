#!/bin/bash
# Netdata custom collector for Rails HTTP metrics
# Parses production.log to extract response time, status codes, and error rates

CHART_NAME="rails_http"
UPDATE_EVERY=10  # Update every 10 seconds
PRIORITY=90000

# Path to Rails production log
LOG_FILE="/host/app/logs/production.log"

# Temporary file to track last read position
POSITION_FILE="/tmp/netdata-rails-http-position"

# Initialize position file if it doesn't exist
if [ ! -f "$POSITION_FILE" ]; then
    echo "0" > "$POSITION_FILE"
fi

# Define the charts
cat << EOF
CHART ${CHART_NAME}.requests '' "HTTP Requests" "requests/s" "http" "rails.http.requests" line ${PRIORITY} ${UPDATE_EVERY}
DIMENSION total 'total' incremental 1 1
DIMENSION 2xx 'success_2xx' incremental 1 1
DIMENSION 3xx 'redirect_3xx' incremental 1 1
DIMENSION 4xx 'client_error_4xx' incremental 1 1
DIMENSION 5xx 'server_error_5xx' incremental 1 1

CHART ${CHART_NAME}.response_time '' "HTTP Response Time" "milliseconds" "http" "rails.http.response_time" line $((PRIORITY+1)) ${UPDATE_EVERY}
DIMENSION avg 'average' absolute 1 1000
DIMENSION max 'maximum' absolute 1 1000
DIMENSION min 'minimum' absolute 1 1000

CHART ${CHART_NAME}.error_rate '' "5xx Error Rate" "percentage" "http" "rails.http.error_rate" line $((PRIORITY+2)) ${UPDATE_EVERY}
DIMENSION rate '5xx_rate' absolute 1 100

CHART ${CHART_NAME}.success_rate '' "Success Rate (2xx)" "percentage" "http" "rails.http.success_rate" line $((PRIORITY+3)) ${UPDATE_EVERY}
DIMENSION rate '2xx_rate' absolute 1 100
EOF

while true; do
    # Check if log file exists
    if [ ! -f "$LOG_FILE" ]; then
        # Output zeros if log file doesn't exist
        echo "BEGIN ${CHART_NAME}.requests"
        echo "SET total = 0"
        echo "SET 2xx = 0"
        echo "SET 3xx = 0"
        echo "SET 4xx = 0"
        echo "SET 5xx = 0"
        echo "END"

        echo "BEGIN ${CHART_NAME}.response_time"
        echo "SET avg = 0"
        echo "SET max = 0"
        echo "SET min = 0"
        echo "END"

        echo "BEGIN ${CHART_NAME}.error_rate"
        echo "SET rate = 0"
        echo "END"

        echo "BEGIN ${CHART_NAME}.success_rate"
        echo "SET rate = 100"
        echo "END"

        sleep ${UPDATE_EVERY}
        continue
    fi

    # Read last position
    LAST_POS=$(cat "$POSITION_FILE")

    # Get new lines since last read
    CURRENT_SIZE=$(stat -c %s "$LOG_FILE" 2>/dev/null || echo "0")

    # If file was rotated (smaller than last position), start from beginning
    if [ "$CURRENT_SIZE" -lt "$LAST_POS" ]; then
        LAST_POS=0
    fi

    # Read new log lines and parse JSON
    NEW_LOGS=$(tail -c +$((LAST_POS + 1)) "$LOG_FILE" 2>/dev/null)

    # Initialize counters
    TOTAL=0
    COUNT_2XX=0
    COUNT_3XX=0
    COUNT_4XX=0
    COUNT_5XX=0
    TOTAL_DURATION=0
    MAX_DURATION=0
    MIN_DURATION=999999

    # Parse JSON log entries (lograge format)
    while IFS= read -r line; do
        # Check if line contains status and duration (lograge JSON format)
        if echo "$line" | grep -q '"status"' && echo "$line" | grep -q '"duration"'; then
            # Extract status code
            STATUS=$(echo "$line" | grep -o '"status":[0-9]*' | grep -o '[0-9]*')
            # Extract duration in milliseconds
            DURATION=$(echo "$line" | grep -o '"duration":[0-9.]*' | grep -o '[0-9.]*' | awk '{print int($1)}')

            if [ -n "$STATUS" ] && [ -n "$DURATION" ]; then
                TOTAL=$((TOTAL + 1))
                TOTAL_DURATION=$((TOTAL_DURATION + DURATION))

                # Update min/max
                if [ "$DURATION" -gt "$MAX_DURATION" ]; then
                    MAX_DURATION=$DURATION
                fi
                if [ "$DURATION" -lt "$MIN_DURATION" ]; then
                    MIN_DURATION=$DURATION
                fi

                # Categorize by status code
                if [ "$STATUS" -ge 200 ] && [ "$STATUS" -lt 300 ]; then
                    COUNT_2XX=$((COUNT_2XX + 1))
                elif [ "$STATUS" -ge 300 ] && [ "$STATUS" -lt 400 ]; then
                    COUNT_3XX=$((COUNT_3XX + 1))
                elif [ "$STATUS" -ge 400 ] && [ "$STATUS" -lt 500 ]; then
                    COUNT_4XX=$((COUNT_4XX + 1))
                elif [ "$STATUS" -ge 500 ] && [ "$STATUS" -lt 600 ]; then
                    COUNT_5XX=$((COUNT_5XX + 1))
                fi
            fi
        fi
    done <<< "$NEW_LOGS"

    # Calculate averages
    if [ "$TOTAL" -gt 0 ]; then
        AVG_DURATION=$((TOTAL_DURATION / TOTAL))
        ERROR_RATE=$((COUNT_5XX * 10000 / TOTAL))  # Rate in basis points (0.01%)
        SUCCESS_RATE=$((COUNT_2XX * 10000 / TOTAL))  # Rate in basis points (0.01%)
    else
        AVG_DURATION=0
        ERROR_RATE=0
        SUCCESS_RATE=10000  # 100% if no requests
        MIN_DURATION=0
    fi

    # Save current position
    echo "$CURRENT_SIZE" > "$POSITION_FILE"

    # Output metrics
    echo "BEGIN ${CHART_NAME}.requests"
    echo "SET total = ${TOTAL}"
    echo "SET 2xx = ${COUNT_2XX}"
    echo "SET 3xx = ${COUNT_3XX}"
    echo "SET 4xx = ${COUNT_4XX}"
    echo "SET 5xx = ${COUNT_5XX}"
    echo "END"

    echo "BEGIN ${CHART_NAME}.response_time"
    echo "SET avg = ${AVG_DURATION}"
    echo "SET max = ${MAX_DURATION}"
    echo "SET min = ${MIN_DURATION}"
    echo "END"

    echo "BEGIN ${CHART_NAME}.error_rate"
    echo "SET rate = ${ERROR_RATE}"
    echo "END"

    echo "BEGIN ${CHART_NAME}.success_rate"
    echo "SET rate = ${SUCCESS_RATE}"
    echo "END"

    sleep ${UPDATE_EVERY}
done
