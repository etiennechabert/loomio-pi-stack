# Loomio Pi Stack - Quick Start Guide

This guide will walk you through setting up Loomio on your Raspberry Pi or Linux server in approximately 30 minutes.

## Prerequisites Checklist

Before you begin, ensure you have:

- [ ] Raspberry Pi 4 (4GB+ RAM) or Linux server
- [ ] Fresh Raspberry Pi OS (64-bit recommended) or Ubuntu 20.04+
- [ ] Internet connection
- [ ] Domain name (e.g., loomio.example.com)
- [ ] SMTP credentials (Gmail, SendGrid, Mailgun, etc.)
- [ ] SSH access to your Pi/server

## Step 1: System Preparation (5 minutes)

### Update System

```bash
sudo apt update
sudo apt upgrade -y
```

### Install Docker

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to docker group
sudo usermod -aG docker $USER

# Log out and back in for group changes to take effect
# Or run: newgrp docker

# Verify installation
docker --version
docker compose version
```

### Install Dependencies

```bash
sudo apt install -y git openssl
```

## Step 2: Clone Repository (2 minutes)

```bash
# Navigate to home directory
cd ~

# Clone the repository
git clone https://github.com/yourusername/loomio-pi-stack.git

# Enter directory
cd loomio-pi-stack
```

## Step 3: Configure Environment (10 minutes)

### Copy Environment Template

```bash
cp .env.example .env
```

### Generate Secrets

Generate required encryption keys:

```bash
# Generate all secrets at once
echo "SECRET_KEY_BASE=$(openssl rand -hex 64)"
echo "LOOMIO_HMAC_KEY=$(openssl rand -hex 32)"
echo "DEVISE_SECRET=$(openssl rand -hex 32)"
echo "BACKUP_ENCRYPTION_KEY=$(openssl rand -hex 32)"
```

Copy the output and save it somewhere secure!

### Edit Configuration

```bash
nano .env
```

Fill in these **required** fields:

```bash
# Domain Configuration
CANONICAL_HOST=loomio.example.com  # Your domain
SUPPORT_EMAIL=support@example.com

# Database Password
POSTGRES_PASSWORD=your-secure-database-password

# Secret Keys (paste generated values)
SECRET_KEY_BASE=paste-generated-value
LOOMIO_HMAC_KEY=paste-generated-value
DEVISE_SECRET=paste-generated-value
BACKUP_ENCRYPTION_KEY=paste-generated-value

# SMTP Configuration (example for Gmail)
SMTP_DOMAIN=gmail.com
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_AUTH=plain
SMTP_USE_TLS=true

# Email Settings
REPLY_HOSTNAME=loomio.example.com
FROM_EMAIL=noreply@example.com
HELPER_BOT_EMAIL=noreply@example.com
```

**Save and exit** (Ctrl+X, Y, Enter)

### SMTP Provider Examples

#### Gmail
```bash
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password  # Generate at https://myaccount.google.com/apppasswords
```

#### SendGrid
```bash
SMTP_SERVER=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=your-sendgrid-api-key
```

#### Mailgun
```bash
SMTP_SERVER=smtp.mailgun.org
SMTP_PORT=587
SMTP_USERNAME=postmaster@your-domain.mailgun.org
SMTP_PASSWORD=your-mailgun-password
```

## Step 4: DNS Configuration (5 minutes)

Configure your domain's DNS settings:

### Required DNS Records

| Type | Name | Value | TTL |
|------|------|-------|-----|
| A | loomio | YOUR_SERVER_IP | 300 |
| CNAME | channels | loomio.example.com | 300 |
| CNAME | hocuspocus | loomio.example.com | 300 |
| MX | @ | loomio.example.com | 300 |

### Wait for DNS Propagation

```bash
# Check if DNS is ready (replace with your domain)
nslookup loomio.example.com
```

## Step 5: Start Loomio (5 minutes)

### Build and Start Services

```bash
# Build backup service
docker compose build backup

# Pull all images
docker compose pull

# Start all services
docker compose up -d
```

### Initialize Database

```bash
# Wait for database to be ready (about 30 seconds)
sleep 30

# Initialize database schema
docker compose run app rake db:setup
```

### Verify Services

```bash
# Check all services are running
docker compose ps

# Should show all services as "Up" or "Up (healthy)"
```

### View Logs

```bash
# Watch logs from all services
docker compose logs -f

# Press Ctrl+C to stop watching
```

## Step 6: Access Loomio (2 minutes)

### Web Interface

Open your browser and go to:
```
http://YOUR_SERVER_IP:3000
```

Or if DNS is configured:
```
https://loomio.example.com
```

### Create First User

1. Click "Sign up"
2. Fill in your details
3. Submit the form
4. Check your email for confirmation link
5. Click the confirmation link

### Make Yourself Admin

```bash
# After confirming your email
docker compose run app rails c

# In the Rails console, type:
User.last.update(is_admin: true)
exit
```

## Step 7: Configure Automatic Startup (Optional) (3 minutes)

### Enable Systemd Services

```bash
# Copy service files
sudo cp loomio.service /etc/systemd/system/
sudo cp loomio-watchdog.service /etc/systemd/system/
sudo cp loomio-watchdog.timer /etc/systemd/system/

# Update WorkingDirectory in service file to match your path
sudo sed -i "s|/home/pi/loomio-pi-stack|$(pwd)|g" /etc/systemd/system/loomio.service

# Reload systemd
sudo systemctl daemon-reload

# Enable services
sudo systemctl enable loomio.service
sudo systemctl enable loomio-watchdog.timer

# Start watchdog timer
sudo systemctl start loomio-watchdog.timer

# Verify status
sudo systemctl status loomio.service
```

Now Loomio will start automatically on boot!

## Step 8: Access Additional Services

### Netdata Monitoring
```
http://YOUR_SERVER_IP:19999
```

### Database Admin (Adminer)
```
http://YOUR_SERVER_IP:8081
```
- System: PostgreSQL
- Server: db
- Username: loomio
- Password: (from your .env file)

### Channels (Real-time)
```
http://YOUR_SERVER_IP:5000
```

### Hocuspocus (Collaborative Editing)
```
http://YOUR_SERVER_IP:4000
```

## Verification Checklist

- [ ] All containers are running: `docker compose ps`
- [ ] Can access Loomio web interface
- [ ] Email confirmation was received
- [ ] Can log in as admin
- [ ] Netdata dashboard is accessible
- [ ] Backups directory exists: `ls -lh backups/`
- [ ] First backup was created

## Next Steps

### Security Hardening
1. Set up HTTPS with Let's Encrypt or Cloudflare
2. Configure firewall rules
3. Review [SECURITY.md](SECURITY.md)

### Configure Backups
1. Set up Google Drive sync (optional)
2. Test restore procedure
3. Review [BACKUP_GUIDE.md](BACKUP_GUIDE.md)

### Customization
1. Add custom logo (in .env: `THEME_LOGO_URL`)
2. Change theme colors (in .env: `THEME_PRIMARY_COLOR`)
3. Configure notification settings

## Troubleshooting

### Containers Won't Start

```bash
# Check logs
docker compose logs app

# Common fixes
docker compose down
docker compose up -d
```

### Can't Access Web Interface

```bash
# Check if port is listening
sudo netstat -tlnp | grep 3000

# Check firewall
sudo ufw status
sudo ufw allow 3000/tcp
```

### Database Errors

```bash
# Reset database
docker compose down
docker volume rm loomio-pi-stack_db-data
docker compose up -d
sleep 30
docker compose run app rake db:setup
```

### Email Not Sending

```bash
# Test SMTP settings
docker compose run app rails c

# In Rails console:
ActionMailer::Base.smtp_settings
# Verify settings match your .env file
```

### Out of Memory

```bash
# Check memory usage
free -h

# If low, increase swap:
sudo dphys-swapfile swapoff
sudo nano /etc/dphys-swapfile
# Change CONF_SWAPSIZE=100 to CONF_SWAPSIZE=2048
sudo dphys-swapfile setup
sudo dphys-swapfile swapon
```

## Getting Help

- Check logs: `docker compose logs -f`
- Review [README.md](README.md) for detailed documentation
- Loomio Help: https://help.loomio.com/
- Open an issue: https://github.com/yourusername/loomio-pi-stack/issues

## Useful Commands

```bash
# Stop all services
docker compose down

# Restart all services
docker compose restart

# Update all containers
docker compose pull
docker compose up -d

# View resource usage
docker stats

# Manual backup
docker compose exec backup python3 /app/backup.py

# Access database
docker compose exec db psql -U loomio -d loomio_production

# Rails console
docker compose run app rails c

# Check service health
./scripts/watchdog/health-monitor.sh
```

## Success! 🎉

You now have a fully functional Loomio instance running on your Raspberry Pi!

Start creating groups and making collaborative decisions at:
```
http://YOUR_SERVER_IP:3000
```

---

**Need help?** Check the [README.md](README.md) or open an issue on GitHub.
