FROM python:3.11-slim

# Install PostgreSQL client for pg_dump
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-client \
    cron \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy backup scripts, sync scripts and entrypoint, make executable, and create backup directory
COPY backup.py sync-files-to-gdrive.py entrypoint.sh ./
RUN chmod +x backup.py sync-files-to-gdrive.py entrypoint.sh && \
    mkdir -p /backups

ENTRYPOINT ["/app/entrypoint.sh"]
