#!/bin/bash
# Netdata custom collector for Google Drive sync status
# Reports time since last successful sync

CHART_NAME="loomio_gdrive_sync"
UPDATE_EVERY=60  # Update every 60 seconds
PRIORITY=90001

# Get the status file location
STATUS_FILE="/host/production/backups/.last_sync_status"

# Define the chart
cat << EOF
CHART ${CHART_NAME}.age '' "Google Drive Sync Age" "seconds" "backups" "loomio.gdrive.sync.age" line ${PRIORITY} ${UPDATE_EVERY}
DIMENSION age 'age' absolute 1 1
CHART ${CHART_NAME}.status '' "Google Drive Sync Status" "status" "backups" "loomio.gdrive.sync.status" line ${PRIORITY} ${UPDATE_EVERY}
DIMENSION status 'status' absolute 1 1
EOF

while true; do
    CURRENT_TIME=$(date +%s)
    
    if [ -f "${STATUS_FILE}" ]; then
        CONTENT=$(cat "${STATUS_FILE}" 2>/dev/null)
        
        if [ "${CONTENT}" = "error" ]; then
            # Sync error
            AGE=999999
            STATUS=0
        elif [[ "${CONTENT}" =~ ^[0-9]+$ ]]; then
            # Successful sync timestamp
            AGE=$((CURRENT_TIME - CONTENT))
            STATUS=1
        else
            # Unknown status
            AGE=999999
            STATUS=0
        fi
    else
        # No status file - never synced
        AGE=999999
        STATUS=0
    fi
    
    # Output the values
    echo "BEGIN ${CHART_NAME}.age"
    echo "SET age = ${AGE}"
    echo "END"
    
    echo "BEGIN ${CHART_NAME}.status"
    echo "SET status = ${STATUS}"
    echo "END"
    
    sleep ${UPDATE_EVERY}
done
