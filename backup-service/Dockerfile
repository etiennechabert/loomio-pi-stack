FROM python:3.11-slim

# Install PostgreSQL client for pg_dump
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    postgresql-client \
    cron \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy requirements and install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy backup script and entrypoint
COPY backup.py .
COPY entrypoint.sh .

# Make scripts executable
RUN chmod +x backup.py entrypoint.sh

# Create backup directory
RUN mkdir -p /backups

ENTRYPOINT ["/app/entrypoint.sh"]
