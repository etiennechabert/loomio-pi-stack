# Restore on Boot - Stateless Operation

Configure your Loomio Pi to automatically restore from the latest backup on every boot, enabling true stateless operation.

## Table of Contents
- [Why Stateless Operation?](#why-stateless-operation)
- [How It Works](#how-it-works)
- [Setup Instructions](#setup-instructions)
- [Use Cases](#use-cases)
- [Limitations](#limitations)
- [Troubleshooting](#troubleshooting)

## Why Stateless Operation?

### Benefits

1. **SD Card Protection** - Prevents SD card wear from database writes
2. **Easy Recovery** - Fresh start on every boot
3. **Consistency** - Known good state always restored
4. **Testing** - Safe to experiment, reboot restores
5. **Read-Only Root** - Can run with read-only filesystem

### When to Use

- **Development/Testing** - Experiment without consequences
- **Demo Systems** - Always start with clean demo data
- **Read-Only Deployments** - Industrial/embedded systems
- **Disaster Recovery** - Quick recovery after crashes

### When NOT to Use

- **Production Systems** - Data loss risk on unexpected reboot
- **High-Write Applications** - Frequent changes would be lost
- **24/7 Services** - Reboots interrupt service

## How It Works

```
┌─────────────────────────────────────────────────┐
│              System Boot Sequence               │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│  1. systemd starts loomio.service               │
│     • Starts Docker Compose                     │
│     • All containers launch                     │
│     • Database initializes (empty)              │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│  2. restore-on-boot.sh runs                     │
│     • Finds latest backup                       │
│     • Decrypts if needed                        │
│     • Drops empty database                      │
│     • Restores backup data                      │
└─────────────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────┐
│  3. Services restart with restored data         │
│     • Loomio app ready                          │
│     • Data from last backup                     │
└─────────────────────────────────────────────────┘
```

## Setup Instructions

### Step 1: Ensure Backups Are Working

```bash
# Verify backups exist
ls -lh backups/

# Should see recent backups like:
# loomio_backup_20240115_120000.sql.enc

# Create manual backup if needed
docker compose exec backup python3 /app/backup.py
```

### Step 2: Test Restore Script

```bash
# Test the restore process manually
./scripts/restore-on-boot.sh

# Verify it works without errors
# This will restore the latest backup
```

### Step 3: Create systemd Service

Create `/etc/systemd/system/loomio-restore.service`:

```bash
sudo nano /etc/systemd/system/loomio-restore.service
```

```ini
[Unit]
Description=Loomio Restore on Boot
After=loomio.service
Requires=loomio.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/pi/loomio-pi-stack
ExecStart=/home/pi/loomio-pi-stack/scripts/restore-on-boot.sh
StandardOutput=journal
StandardError=journal
User=pi
Group=pi

# Wait for database to be ready
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
```

### Step 4: Enable Auto-Restore

```bash
# Reload systemd
sudo systemctl daemon-reload

# Enable restore on boot
sudo systemctl enable loomio-restore.service

# Verify configuration
sudo systemctl status loomio-restore.service
```

### Step 5: Test Full Boot Sequence

```bash
# Reboot system
sudo reboot

# After reboot, check status
sudo systemctl status loomio.service
sudo systemctl status loomio-restore.service

# Check logs
journalctl -u loomio-restore.service -f

# Verify data was restored
docker compose exec db psql -U loomio -d loomio_production -c "SELECT COUNT(*) FROM users;"
```

## Advanced Configuration

### Read-Only Root Filesystem

For ultimate SD card protection:

#### 1. Enable Overlay Filesystem

```bash
# Edit boot config
sudo nano /boot/cmdline.txt

# Add at the end (one line):
init=/usr/lib/raspi-config/init_resize.sh overlayroot=tmpfs
```

#### 2. Mount Backup Directory from USB

```bash
# Plug in USB drive
lsblk

# Create mount point
sudo mkdir -p /mnt/backups

# Auto-mount in /etc/fstab
sudo nano /etc/fstab

# Add:
/dev/sda1 /mnt/backups ext4 defaults,nofail 0 0

# Update backup location in docker-compose.yml
volumes:
  - /mnt/backups:/backups
```

#### 3. Reboot

```bash
sudo reboot

# After boot, root is read-only
mount | grep overlayroot
```

### Scheduled Backup Before Shutdown

Create `/etc/systemd/system/loomio-backup-shutdown.service`:

```ini
[Unit]
Description=Backup Loomio Before Shutdown
DefaultDependencies=no
Before=shutdown.target

[Service]
Type=oneshot
ExecStart=/usr/bin/docker compose -f /home/pi/loomio-pi-stack/docker-compose.yml exec -T backup python3 /app/backup.py
WorkingDirectory=/home/pi/loomio-pi-stack

[Install]
WantedBy=shutdown.target
```

Enable:

```bash
sudo systemctl enable loomio-backup-shutdown.service
```

### Dual-Mode Operation

Switch between stateless and stateful:

```bash
# Disable restore on boot (stateful mode)
sudo systemctl disable loomio-restore.service

# Enable restore on boot (stateless mode)
sudo systemctl enable loomio-restore.service

# Check current mode
systemctl is-enabled loomio-restore.service
```

## Use Cases

### Use Case 1: Demo System

Perfect for showing Loomio at conferences:

```bash
# Before event
1. Set up demo data
2. Create backup
3. Enable restore-on-boot

# At event
- Demonstrate features
- Let people experiment
- Reboot between demos for clean state

# After event
- Disable restore-on-boot
- Return to normal operation
```

### Use Case 2: Development Environment

Safe experimentation:

```bash
# Morning routine
1. Boot Pi (auto-restores last night's backup)
2. Make changes/test features
3. If something breaks, just reboot

# End of day
- Manual backup if changes should be kept
- Otherwise, next boot restores yesterday's state
```

### Use Case 3: Read-Only Production

For kiosks or embedded systems:

```bash
# Setup
1. Configure read-only root
2. Mount backups from external storage
3. Enable restore on boot

# Operation
- System is immutable
- No SD card writes (except backups to USB)
- Power failures safe
- Automatic recovery
```

### Use Case 4: Testing Updates

Safe update testing:

```bash
# Test update
1. Create backup
2. Update Loomio
3. Test new version
4. If issues: reboot to restore old version
5. If good: create new backup

# Rollback
sudo reboot  # Automatically restores pre-update state
```

## Limitations

### Data Loss Scenarios

⚠️ **Important**: Data created after last backup will be lost on reboot!

```
Last Backup: 10:00 AM
New Posts: 10:30 AM
Reboot: 11:00 AM
Result: Posts from 10:30 AM are GONE
```

### Mitigation Strategies

#### 1. Frequent Backups

```bash
# Backup every 15 minutes
BACKUP_SCHEDULE=*/15 * * * *
```

#### 2. Pre-Shutdown Backup

Already configured in advanced section.

#### 3. External Backup Trigger

```bash
# Add button to trigger backup
# Raspberry Pi GPIO button example

# /usr/local/bin/backup-button.py
import RPi.GPIO as GPIO
import subprocess

GPIO.setmode(GPIO.BCM)
GPIO.setup(17, GPIO.IN, pull_up_down=GPIO.PUD_UP)

def backup_callback(channel):
    subprocess.run(['docker', 'compose', 'exec', 'backup',
                   'python3', '/app/backup.py'])
    print("Backup triggered!")

GPIO.add_event_detect(17, GPIO.FALLING,
                     callback=backup_callback,
                     bouncetime=2000)

GPIO.wait_for_edge(17, GPIO.FALLING)
```

### Performance Considerations

- **Boot Time**: +30-60 seconds for restore
- **Disk I/O**: Spike during restore
- **Network**: Unavailable during restore

### Not Suitable For

- ❌ High-uptime requirements (99.9%+)
- ❌ High-frequency data changes
- ❌ Systems that can't tolerate data loss
- ❌ Large databases (>10GB) - slow restore

## Monitoring

### Check Restore Status

```bash
# View restore logs
journalctl -u loomio-restore.service -b

# Check if restore succeeded
sudo systemctl status loomio-restore.service

# Should show: "Active: inactive (dead)" with "ExitCode=0/SUCCESS"
```

### Automated Alerts

Add health check:

```bash
# /usr/local/bin/check-restore-health.sh
#!/bin/bash

# Check if restore service succeeded
if ! systemctl is-active loomio-restore.service > /dev/null; then
    echo "ERROR: Restore service not active" >&2
    # Send alert
    exit 1
fi

# Check database is populated
USER_COUNT=$(docker compose exec -T db psql -U loomio -d loomio_production -t -c "SELECT COUNT(*) FROM users;" | xargs)

if [ "$USER_COUNT" -lt 1 ]; then
    echo "ERROR: Database appears empty" >&2
    # Send alert
    exit 1
fi

echo "Restore health check passed: $USER_COUNT users"
```

Run via cron:

```bash
# Check 5 minutes after boot
@reboot sleep 300 && /usr/local/bin/check-restore-health.sh
```

## Troubleshooting

### Restore Fails on Boot

```bash
# Check logs
journalctl -u loomio-restore.service -b

# Common issues:

# 1. No backups found
ls -lh /home/pi/loomio-pi-stack/backups/

# 2. Database not ready
# Increase TimeoutStartSec in service file

# 3. Permission issues
sudo chown -R pi:pi /home/pi/loomio-pi-stack/backups/

# 4. Encryption key missing
grep BACKUP_ENCRYPTION_KEY /home/pi/loomio-pi-stack/.env
```

### Boot Takes Too Long

```bash
# Check restore duration
journalctl -u loomio-restore.service -b | grep "took"

# Optimize:
# 1. Use smaller backups (compress)
# 2. Store backups on faster storage (SSD)
# 3. Reduce backup frequency
```

### Database Appears Empty After Restore

```bash
# Manually verify backup
./scripts/restore-db.sh

# Check backup file integrity
ls -lh backups/

# Try decrypting manually
# See BACKUP_GUIDE.md for decryption instructions
```

### Service Order Issues

```bash
# Ensure correct ordering
systemctl list-dependencies loomio-restore.service

# Should show:
# loomio-restore.service
# ├─loomio.service
# │ └─docker.service

# Fix if needed
sudo systemctl edit loomio-restore.service

# Add:
[Unit]
After=loomio.service docker.service
Requires=loomio.service
```

## Verification

### Verify Stateless Mode Is Active

```bash
# Check service enabled
systemctl is-enabled loomio-restore.service
# Should return: enabled

# Check last restore
journalctl -u loomio-restore.service -b --no-pager

# Test stateless behavior
# 1. Create test data
docker compose run app rails c
# > User.create!(email: 'test@test.com', password: 'testtest')

# 2. Reboot
sudo reboot

# 3. Check if test user exists (should NOT)
docker compose run app rails c
# > User.find_by(email: 'test@test.com')
# Should return: nil
```

## Best Practices

### ✅ Do

- Test restore process thoroughly before enabling
- Keep multiple backup versions
- Monitor restore success after each boot
- Document your restore schedule
- Use external storage for backups
- Create pre-shutdown backups

### ❌ Don't

- Use on production systems without understanding risks
- Rely on a single backup
- Ignore restore failure alerts
- Use with very large databases
- Forget to test after system updates

---

**Stateless operation gives you immutability and recovery, but requires careful planning!** 🔄
