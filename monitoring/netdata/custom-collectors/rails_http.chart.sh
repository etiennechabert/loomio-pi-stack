#!/bin/bash
# Netdata custom collector for Rails HTTP metrics
# Parses production.log to extract response time, status codes, and error rates
# Tracks hourly metrics for 5xx rate and response time percentiles

CHART_NAME="rails_http"
UPDATE_EVERY=10  # Update every 10 seconds
PRIORITY=90000

# Path to Rails production log
LOG_FILE="/host/app/logs/production.log"

# Temporary file to track last read position
POSITION_FILE="/tmp/netdata-rails-http-position"

# Temporary file to store hourly metrics data
HOURLY_DATA_FILE="/tmp/netdata-rails-http-hourly-data"

# Initialize position file if it doesn't exist
if [ ! -f "$POSITION_FILE" ]; then
    echo "0" > "$POSITION_FILE"
fi

# Initialize hourly data file if it doesn't exist
if [ ! -f "$HOURLY_DATA_FILE" ]; then
    echo "" > "$HOURLY_DATA_FILE"
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
DIMENSION p50 'p50_median' absolute 1 1000
DIMENSION p90 'p90' absolute 1 1000
DIMENSION p99 'p99' absolute 1 1000
DIMENSION max 'maximum' absolute 1 1000

CHART ${CHART_NAME}.response_time_hourly '' "HTTP Response Time (1 Hour)" "milliseconds" "http" "rails.http.response_time_hourly" line $((PRIORITY+2)) ${UPDATE_EVERY}
DIMENSION p50 'p50_median' absolute 1 1000
DIMENSION p90 'p90' absolute 1 1000

CHART ${CHART_NAME}.error_rate '' "5xx Error Rate (10s)" "percentage" "http" "rails.http.error_rate" line $((PRIORITY+3)) ${UPDATE_EVERY}
DIMENSION rate '5xx_rate' absolute 1 100

CHART ${CHART_NAME}.error_rate_hourly '' "5xx Error Rate (1 Hour)" "percentage" "http" "rails.http.error_rate_hourly" line $((PRIORITY+4)) ${UPDATE_EVERY}
DIMENSION rate '5xx_rate' absolute 1 100
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
        echo "SET p50 = 0"
        echo "SET p90 = 0"
        echo "SET p99 = 0"
        echo "SET max = 0"
        echo "END"

        echo "BEGIN ${CHART_NAME}.response_time_hourly"
        echo "SET p50 = 0"
        echo "SET p90 = 0"
        echo "END"

        echo "BEGIN ${CHART_NAME}.error_rate"
        echo "SET rate = 0"
        echo "END"

        echo "BEGIN ${CHART_NAME}.error_rate_hourly"
        echo "SET rate = 0"
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

    # Current timestamp
    CURRENT_TIME=$(date +%s)
    ONE_HOUR_AGO=$((CURRENT_TIME - 3600))

    # Initialize counters
    TOTAL=0
    COUNT_2XX=0
    COUNT_3XX=0
    COUNT_4XX=0
    COUNT_5XX=0
    MAX_DURATION=0
    declare -a DURATIONS=()

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
                DURATIONS+=("$DURATION")

                # Update max
                if [ "$DURATION" -gt "$MAX_DURATION" ]; then
                    MAX_DURATION=$DURATION
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

                # Append to hourly data file with timestamp
                echo "${CURRENT_TIME}|${STATUS}|${DURATION}" >> "$HOURLY_DATA_FILE"
            fi
        fi
    done <<< "$NEW_LOGS"

    # Calculate percentiles for current interval
    P50=0
    P90=0
    P99=0
    if [ "${#DURATIONS[@]}" -gt 0 ]; then
        # Sort durations
        IFS=$'\n' SORTED=($(sort -n <<<"${DURATIONS[*]}"))
        unset IFS

        COUNT=${#SORTED[@]}
        P50_INDEX=$(( (COUNT * 50) / 100 ))
        P90_INDEX=$(( (COUNT * 90) / 100 ))
        P99_INDEX=$(( (COUNT * 99) / 100 ))

        P50=${SORTED[$P50_INDEX]:-0}
        P90=${SORTED[$P90_INDEX]:-0}
        P99=${SORTED[$P99_INDEX]:-0}
    fi

    # Calculate current interval error rate
    if [ "$TOTAL" -gt 0 ]; then
        ERROR_RATE=$((COUNT_5XX * 10000 / TOTAL))  # Rate in basis points (0.01%)
    else
        ERROR_RATE=0
    fi

    # Clean up old hourly data (older than 1 hour)
    if [ -f "$HOURLY_DATA_FILE" ]; then
        grep -v "^$" "$HOURLY_DATA_FILE" | awk -F'|' -v cutoff="$ONE_HOUR_AGO" '$1 >= cutoff' > "${HOURLY_DATA_FILE}.tmp"
        mv "${HOURLY_DATA_FILE}.tmp" "$HOURLY_DATA_FILE"
    fi

    # Calculate hourly metrics
    HOURLY_TOTAL=0
    HOURLY_5XX=0
    declare -a HOURLY_DURATIONS=()

    while IFS='|' read -r timestamp status duration; do
        [ -z "$timestamp" ] && continue
        HOURLY_TOTAL=$((HOURLY_TOTAL + 1))
        HOURLY_DURATIONS+=("$duration")
        if [ "$status" -ge 500 ] && [ "$status" -lt 600 ]; then
            HOURLY_5XX=$((HOURLY_5XX + 1))
        fi
    done < "$HOURLY_DATA_FILE"

    # Calculate hourly percentiles
    HOURLY_P50=0
    HOURLY_P90=0
    if [ "${#HOURLY_DURATIONS[@]}" -gt 0 ]; then
        IFS=$'\n' HOURLY_SORTED=($(sort -n <<<"${HOURLY_DURATIONS[*]}"))
        unset IFS

        HOURLY_COUNT=${#HOURLY_SORTED[@]}
        HOURLY_P50_INDEX=$(( (HOURLY_COUNT * 50) / 100 ))
        HOURLY_P90_INDEX=$(( (HOURLY_COUNT * 90) / 100 ))

        HOURLY_P50=${HOURLY_SORTED[$HOURLY_P50_INDEX]:-0}
        HOURLY_P90=${HOURLY_SORTED[$HOURLY_P90_INDEX]:-0}
    fi

    # Calculate hourly error rate
    if [ "$HOURLY_TOTAL" -gt 0 ]; then
        HOURLY_ERROR_RATE=$((HOURLY_5XX * 10000 / HOURLY_TOTAL))  # Rate in basis points (0.01%)
    else
        HOURLY_ERROR_RATE=0
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
    echo "SET p50 = ${P50}"
    echo "SET p90 = ${P90}"
    echo "SET p99 = ${P99}"
    echo "SET max = ${MAX_DURATION}"
    echo "END"

    echo "BEGIN ${CHART_NAME}.response_time_hourly"
    echo "SET p50 = ${HOURLY_P50}"
    echo "SET p90 = ${HOURLY_P90}"
    echo "END"

    echo "BEGIN ${CHART_NAME}.error_rate"
    echo "SET rate = ${ERROR_RATE}"
    echo "END"

    echo "BEGIN ${CHART_NAME}.error_rate_hourly"
    echo "SET rate = ${HOURLY_ERROR_RATE}"
    echo "END"

    sleep ${UPDATE_EVERY}
done
