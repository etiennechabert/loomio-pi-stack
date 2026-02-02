# Security Guide

Security best practices for running Loomio in production.

## Table of Contents
- [Security Checklist](#security-checklist)
- [Authentication & Access](#authentication--access)
- [Network Security](#network-security)
- [Data Protection](#data-protection)
- [Container Security](#container-security)
- [Monitoring & Auditing](#monitoring--auditing)
- [Incident Response](#incident-response)

## Security Checklist

### Essential (Do Before Going Live)

- [ ] Change all default passwords in `.env`
- [ ] Generate strong secret keys (64+ character random strings)
- [ ] Enable HTTPS/SSL for all connections
- [ ] Configure firewall (UFW/iptables)
- [ ] Enable automated backups with encryption
- [ ] Set up off-site backup storage
- [ ] Update system packages
- [ ] Configure SMTP with TLS
- [ ] Review and limit open ports
- [ ] Set up system monitoring

### Recommended

- [ ] Enable two-factor authentication for admin accounts
- [ ] Configure rate limiting
- [ ] Set up intrusion detection (Fail2ban)
- [ ] Enable audit logging
- [ ] Implement least privilege access
- [ ] Regular security updates (Watchtower)
- [ ] Vulnerability scanning
- [ ] Backup encryption key management
- [ ] DDoS protection (Cloudflare)

### Advanced

- [ ] Read-only root filesystem
- [ ] AppArmor/SELinux policies
- [ ] Database connection encryption
- [ ] Container image signing
- [ ] Security headers (CSP, HSTS, etc.)
- [ ] Regular penetration testing
- [ ] Compliance certifications (if needed)

## Authentication & Access

### Strong Passwords

```bash
# Generate secure password
openssl rand -base64 32

# All passwords in .env should be:
# - At least 32 characters
# - Random (not dictionary words)
# - Unique (different for each service)
```

### Secret Keys

```bash
# Generate all required keys
SECRET_KEY_BASE=$(openssl rand -hex 64)
LOOMIO_HMAC_KEY=$(openssl rand -hex 32)
DEVISE_SECRET=$(openssl rand -hex 32)
BACKUP_ENCRYPTION_KEY=$(openssl rand -hex 32)

# Store securely:
# 1. In .env file (never commit to git)
# 2. In password manager (backup)
# 3. In encrypted offline storage (disaster recovery)
```

### SSH Access

```bash
# Disable password authentication
sudo nano /etc/ssh/sshd_config
# Set: PasswordAuthentication no
# Set: PubkeyAuthentication yes

# Use SSH keys only
ssh-keygen -t ed25519 -C "your_email@example.com"

# Restart SSH
sudo systemctl restart sshd
```

### Admin Account Security

```bash
# After creating admin user
docker compose run app rails c

# Enable 2FA (if plugin available)
User.find_by(email: 'admin@example.com').update(require_2fa: true)

# Or limit admin IP access in reverse proxy
```

## Network Security

### Firewall Configuration

```bash
# Install UFW (Uncomplicated Firewall)
sudo apt install ufw

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (change 22 to your SSH port)
sudo ufw allow 22/tcp

# Allow HTTP/HTTPS (if not using Cloudflare Tunnel)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Allow Loomio (if exposing directly)
# sudo ufw allow 3000/tcp

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status verbose
```

### Reverse Proxy (Nginx + SSL)

```nginx
# /etc/nginx/sites-available/loomio
server {
    listen 80;
    server_name loomio.example.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name loomio.example.com;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/loomio.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/loomio.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security Headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Proxy to Loomio
    location / {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Channels
    location /cable {
        proxy_pass http://localhost:5000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # File upload limits
    client_max_body_size 100M;
}
```

### Cloudflare Tunnel (Zero-Trust Access)

```bash
# Enable Cloudflare profile in docker-compose
docker compose --profile cloudflare up -d

# Benefits:
# - No open ports
# - DDoS protection
# - Web Application Firewall
# - Free SSL
# - Access controls
```

### Rate Limiting

Add to nginx configuration:

```nginx
# Define rate limit zone
limit_req_zone $binary_remote_addr zone=loomio:10m rate=10r/s;

# Apply to locations
location / {
    limit_req zone=loomio burst=20 nodelay;
    # ... rest of config
}
```

## Data Protection

### Encryption at Rest

#### Database Encryption

```bash
# PostgreSQL transparent data encryption (TDE)
# Requires PostgreSQL compiled with --with-openssl

# Or use encrypted disk/volume
# Example: LUKS on Linux

sudo cryptsetup luksFormat /dev/sdb
sudo cryptsetup open /dev/sdb loomio-encrypted
sudo mkfs.ext4 /dev/mapper/loomio-encrypted
```

#### Backup Encryption

Already implemented! All backups are encrypted with AES-256.

```bash
# Verify encryption is enabled
grep BACKUP_ENCRYPTION_KEY .env

# Test encryption
docker compose exec backup python3 /app/backup.py
ls -lh backups/*.enc
```

### Encryption in Transit

#### Database Connections

```yaml
# docker-compose.yml - add SSL for PostgreSQL
db:
  command: >
    -c ssl=on
    -c ssl_cert_file=/etc/ssl/certs/server.crt
    -c ssl_key_file=/etc/ssl/private/server.key
```

#### SMTP TLS

Already configured in `.env`:

```bash
SMTP_USE_TLS=true
SMTP_PORT=587  # Use 465 for SSL
```

### Secrets Management

#### Never Commit Secrets

```bash
# .gitignore already includes:
.env
.env.*
!.env.*.example

# Verify
git status  # Should not show .env
```

#### Rotate Secrets Regularly

```bash
# Every 90 days, regenerate:
# - POSTGRES_PASSWORD
# - SECRET_KEY_BASE
# - API tokens

# Update .env, then:
docker compose down
docker compose up -d
```

## Container Security

### Image Security

```bash
# Use official images only
# Check docker-compose.yml for:
# - loomio/loomio:stable (official)
# - postgres:15-alpine (official)
# - redis:7-alpine (official)

# Scan for vulnerabilities
docker scan loomio/loomio:stable
```

### Container Isolation

```yaml
# Already implemented in docker-compose.yml:
# - Dedicated network (loomio-network)
# - No unnecessary ports exposed
# - Health checks
# - Resource limits (optional)

# Add resource limits:
services:
  app:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '1'
          memory: 1G
```

### Read-Only Containers

```yaml
# For stateless services
services:
  worker:
    read_only: true
    tmpfs:
      - /tmp
      - /loomio/tmp
```

### User Namespaces

```bash
# Enable Docker user namespaces
sudo nano /etc/docker/daemon.json
```

```json
{
  "userns-remap": "default"
}
```

```bash
sudo systemctl restart docker
```

## Monitoring & Auditing

### Log Management

```bash
# Centralize logs
docker compose logs -f > /var/log/loomio.log

# Rotate logs
sudo nano /etc/logrotate.d/loomio
```

```
/var/log/loomio.log {
    daily
    rotate 30
    compress
    delaycompress
    notifempty
    create 0640 root root
}
```

### Failed Login Monitoring

```bash
# In Rails console
docker compose run app rails c

# Check failed login attempts
LoginAttempt.where(success: false).where('created_at > ?', 1.day.ago).count

# Block suspicious IPs in nginx or Cloudflare
```

### Intrusion Detection

```bash
# Install Fail2ban
sudo apt install fail2ban

# Configure for nginx
sudo nano /etc/fail2ban/jail.local
```

```ini
[nginx-limit-req]
enabled = true
filter = nginx-limit-req
logpath = /var/log/nginx/error.log
maxretry = 10
findtime = 600
bantime = 7200
```

### Netdata Security Alerts

Already configured in `monitoring/netdata/health.d/loomio.conf`

View alerts:
```bash
http://your-server:19999/api/v1/alarms
```

## Incident Response

### Security Incident Plan

1. **Detect**: Monitoring alerts, user reports
2. **Contain**: Disable affected services/accounts
3. **Investigate**: Check logs, database, backups
4. **Remediate**: Patch vulnerabilities, restore from backup
5. **Review**: Update security policies

### Compromise Response

```bash
# 1. Immediately disconnect from network
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default deny outgoing

# 2. Stop all services
docker compose down

# 3. Preserve logs
cp -r /var/lib/docker/containers /forensics/
docker compose logs > /forensics/loomio-logs.txt

# 4. Investigate
# Check for:
# - Unauthorized database access
# - Modified files
# - Unusual processes

# 5. Restore from clean backup
./scripts/restore-db.sh

# 6. Update all secrets
nano .env  # Change all passwords and keys

# 7. Restart with new configuration
docker compose up -d

# 8. Force all users to reset passwords
docker compose run app rails c
User.update_all(reset_password_token: SecureRandom.hex)
```

### Data Breach Response

```bash
# 1. Determine scope
docker compose exec db psql -U loomio -d loomio_production

# Check access logs
SELECT * FROM events WHERE created_at > 'YYYY-MM-DD';

# 2. Notify affected users
# Via Loomio interface or email

# 3. Force password resets
docker compose run app rails c
User.where(email: affected_emails).update_all(
  reset_password_token: SecureRandom.hex,
  reset_password_sent_at: Time.now
)

# 4. Document incident
# - What was accessed
# - When it occurred
# - Who was affected
# - What actions were taken

# 5. Regulatory compliance
# - GDPR: Notify within 72 hours
# - CCPA: Notify without unreasonable delay
# - Check local regulations
```

## Compliance

### GDPR Compliance

```bash
# Enable user data export
docker compose run app rails c

# Export user data
user = User.find_by(email: 'user@example.com')
user.export_data  # If implemented

# Delete user data (right to be forgotten)
user.destroy
```

### Audit Trail

```bash
# Enable comprehensive logging
# In .env add:
RAILS_LOG_LEVEL=info

# Query audit events
docker compose exec db psql -U loomio -d loomio_production -c \
  "SELECT * FROM events WHERE kind='user_login' ORDER BY created_at DESC LIMIT 100;"
```

## Security Updates

### Automated Updates

Already enabled via Watchtower:

```bash
# Check Watchtower logs
docker compose logs watchtower

# Manual update
docker compose pull
docker compose up -d
```

### Security Mailing Lists

Subscribe to:
- Loomio security announcements
- PostgreSQL security
- Docker security notices

### Vulnerability Scanning

```bash
# Scan containers
docker scan loomio-app

# Scan host
sudo apt install lynis
sudo lynis audit system
```

## Secure Defaults

This stack already implements:

✅ **Network Isolation** - Dedicated Docker network
✅ **Health Checks** - Automatic service monitoring
✅ **Encrypted Backups** - AES-256 encryption
✅ **Auto-updates** - Watchtower for patches
✅ **Monitoring** - Netdata with alerts
✅ **Log Management** - Centralized logging
✅ **Least Privilege** - Minimal container permissions
✅ **Secret Management** - Environment-based secrets

## Additional Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [Loomio Security](https://www.loomio.com/security)
- [PostgreSQL Security](https://www.postgresql.org/docs/current/security.html)

---

**Security is a process, not a product. Stay vigilant!** 🔒
