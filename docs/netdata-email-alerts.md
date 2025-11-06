# Netdata Email Alerts Setup

## Current Status
Netdata is detecting unhealthy containers but email notifications are failing with:
```
sendmail: account default not found: no configuration file available
```

## Required Configuration

### 1. Configure SMTP in `.env`
These environment variables are already defined but need proper values:
- `ALERT_EMAIL` - Email address to receive alerts
- `SMTP_SERVER` - SMTP server address (e.g., smtp.gmail.com)
- `SMTP_PORT` - SMTP port (usually 587 for TLS, 465 for SSL)
- `SMTP_USERNAME` - SMTP username (usually your email address)
- `SMTP_PASSWORD` - SMTP password or app-specific password

### 2. Configure Netdata's `msmtp` or `ssmtp`
Netdata uses either `msmtp` or `ssmtp` for sending emails. We need to:
1. Mount a configuration file for the email client
2. Configure proper TLS/SSL settings
3. Test email delivery

### 3. Health Alarm Configuration
Current alerts that would trigger emails:
- Container unhealthy status (loomio-channels, loomio-hocuspocus)
- High CPU/memory usage
- Disk space warnings
- Service failures

## Implementation Tasks

- [ ] Add msmtp configuration file to `monitoring/netdata/`
- [ ] Mount msmtp config in docker-compose.yml
- [ ] Update `.env.production` template with SMTP examples
- [ ] Add `make test-alerts` command to send test notification
- [ ] Document how to use Gmail/Outlook/custom SMTP

## References
- [Netdata Email Notifications](https://learn.netdata.cloud/docs/alerting/notifications/email)
- [msmtp Configuration](https://marlam.de/msmtp/documentation/)

## Notes
- Consider using app-specific passwords for Gmail
- May want to rate-limit alerts to avoid spam
- Current unhealthy containers (channels/hocuspocus) should be investigated separately
