FROM python:3.11-slim

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install PostgreSQL client, cron, and rclone
# hadolint ignore=DL3008
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-client \
    cron \
    curl \
    unzip \
    ca-certificates \
    && curl https://rclone.org/install.sh | bash \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy backup scripts and make executable
COPY backup.py cleanup-gdrive.py \
     backup-and-sync.sh sync-data.sh \
     backup-minute.sh backup-hourly.sh backup-daily.sh backup-monthly.sh \
     entrypoint.sh ./
RUN chmod +x backup.py cleanup-gdrive.py \
             backup-and-sync.sh sync-data.sh \
             backup-minute.sh backup-hourly.sh backup-daily.sh backup-monthly.sh \
             entrypoint.sh && \
    mkdir -p /backups

ENTRYPOINT ["/app/entrypoint.sh"]
