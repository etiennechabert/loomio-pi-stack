#!/bin/bash
# Netdata custom collector for Loomio backup age
# Reports age of latest backup in data/production/backups/

CHART_NAME="loomio_backup"
UPDATE_EVERY=60  # Update every 60 seconds
PRIORITY=90000

# Get the directory where backups are stored
BACKUP_DIR="/host/data/production/backups"

# Define the chart
cat << EOF
CHART ${CHART_NAME}.age '' "Loomio Backup Age" "seconds" "backups" "loomio.backup.age" line ${PRIORITY} ${UPDATE_EVERY}
DIMENSION age 'age' absolute 1 1
EOF

while true; do
    # Find the newest backup file
    LATEST_BACKUP=$(find "${BACKUP_DIR}" -name "*.sql.enc" -type f -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2)
    
    if [ -n "${LATEST_BACKUP}" ]; then
        # Get file modification time
        FILE_TIME=$(stat -c %Y "${LATEST_BACKUP}" 2>/dev/null)
        CURRENT_TIME=$(date +%s)
        AGE=$((CURRENT_TIME - FILE_TIME))
    else
        # No backup found - set age to a high value
        AGE=999999
    fi
    
    # Output the value
    echo "BEGIN ${CHART_NAME}.age"
    echo "SET age = ${AGE}"
    echo "END"
    
    sleep ${UPDATE_EVERY}
done
