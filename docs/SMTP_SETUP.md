# SMTP Email Setup Guide

Loomio requires email to function properly (for notifications, password resets, etc.). **You do NOT need to run your own mail server!** Instead, you'll use an external SMTP service.

## No Mail Server Container Needed

Unlike some applications, Loomio doesn't require you to run a mail server container. The Loomio app connects directly to an external SMTP service. This is:

- ✅ **Simpler** - No mail server to maintain
- ✅ **More reliable** - Use professional email services
- ✅ **Better deliverability** - Avoid spam filters
- ✅ **Free options available** - Many providers have free tiers

## Quick Setup Options

### Option 1: Gmail (Easiest for Personal Use)

**Free Tier:** 500 emails/day

**Setup:**

1. **Enable 2FA** on your Google account
2. **Generate App Password**:
   - Go to https://myaccount.google.com/apppasswords
   - Select "Mail" and your device
   - Copy the 16-character password

3. **Configure in .env:**

```bash
SMTP_DOMAIN=gmail.com
SMTP_SERVER=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-16-char-app-password
SMTP_AUTH=plain
SMTP_USE_TLS=true

FROM_EMAIL=your-email@gmail.com
REPLY_HOSTNAME=loomio.example.com
```

**Test:**
```bash
make start
make logs-app | grep -i smtp
```

---

### Option 2: SendGrid (Best for Production)

**Free Tier:** 100 emails/day (forever)

**Setup:**

1. **Sign up** at https://sendgrid.com/
2. **Verify your domain** (or sender identity for free tier)
3. **Create API Key**:
   - Settings → API Keys → Create API Key
   - Give it "Full Access" to Mail Send
   - Copy the key (starts with `SG.`)

4. **Configure in .env:**

```bash
SMTP_DOMAIN=your-domain.com
SMTP_SERVER=smtp.sendgrid.net
SMTP_PORT=587
SMTP_USERNAME=apikey
SMTP_PASSWORD=SG.your-api-key-here
SMTP_AUTH=plain
SMTP_USE_TLS=true

FROM_EMAIL=noreply@your-domain.com
REPLY_HOSTNAME=loomio.example.com
```

**Pros:**
- Professional deliverability
- Detailed analytics
- Good documentation
- Reliable

---

### Option 3: Mailgun (Developer Friendly)

**Free Tier:** 5,000 emails/month for 3 months, then paid

**Setup:**

1. **Sign up** at https://www.mailgun.com/
2. **Add and verify domain**
3. **Get SMTP credentials**:
   - Go to Sending → Domain Settings → SMTP credentials
   - Create new credentials

4. **Configure in .env:**

```bash
SMTP_DOMAIN=your-domain.com
SMTP_SERVER=smtp.mailgun.org
SMTP_PORT=587
SMTP_USERNAME=postmaster@mg.your-domain.com
SMTP_PASSWORD=your-mailgun-password
SMTP_AUTH=plain
SMTP_USE_TLS=true

FROM_EMAIL=noreply@your-domain.com
REPLY_HOSTNAME=loomio.example.com
```

**Pros:**
- Developer-friendly API
- Powerful routing
- Good for automated emails

---

### Option 4: Mailtrap (Testing Only)

**Use for:** Development and testing only (emails don't actually send)

**Free Tier:** Unlimited test emails

**Setup:**

1. **Sign up** at https://mailtrap.io/
2. **Get SMTP credentials** from your inbox

3. **Configure in .env:**

```bash
SMTP_SERVER=smtp.mailtrap.io
SMTP_PORT=2525
SMTP_USERNAME=your-mailtrap-username
SMTP_PASSWORD=your-mailtrap-password
SMTP_AUTH=plain
SMTP_USE_TLS=true

FROM_EMAIL=test@loomio.local
```

**Note:** Emails won't actually send - they're caught in Mailtrap for testing.

---

### Option 5: AWS SES (Cheapest at Scale)

**Cost:** $0.10 per 1,000 emails

**Setup:**

1. **Sign up** for AWS
2. **Set up SES** in your region
3. **Create SMTP credentials** in SES console
4. **Verify email/domain**

5. **Configure in .env:**

```bash
SMTP_DOMAIN=your-domain.com
SMTP_SERVER=email-smtp.us-east-1.amazonaws.com
SMTP_PORT=587
SMTP_USERNAME=your-ses-smtp-username
SMTP_PASSWORD=your-ses-smtp-password
SMTP_AUTH=plain
SMTP_USE_TLS=true

FROM_EMAIL=noreply@your-domain.com
```

**Pros:**
- Very cheap at scale
- High deliverability
- Integrates with AWS ecosystem

**Cons:**
- Starts in sandbox mode (limited)
- More complex setup

---

### Option 6: Your Own Domain Email

If you have email hosting with your domain provider:

**Configure in .env:**

```bash
SMTP_DOMAIN=your-domain.com
SMTP_SERVER=smtp.your-provider.com
SMTP_PORT=587  # or 465 for SSL
SMTP_USERNAME=your-email@your-domain.com
SMTP_PASSWORD=your-email-password
SMTP_AUTH=plain
SMTP_USE_TLS=true  # or false if using port 465 SSL

FROM_EMAIL=noreply@your-domain.com
REPLY_HOSTNAME=loomio.your-domain.com
```

Check your email provider's documentation for SMTP settings.

---

## Configuration Details

### Required Environment Variables

```bash
# SMTP Server Settings
SMTP_DOMAIN=example.com           # Your domain
SMTP_SERVER=smtp.example.com      # SMTP server address
SMTP_PORT=587                      # 587 (TLS) or 465 (SSL)
SMTP_USERNAME=user@example.com    # SMTP username
SMTP_PASSWORD=your-password       # SMTP password
SMTP_AUTH=plain                   # Authentication method
SMTP_USE_TLS=true                 # Use TLS encryption

# Email Settings
FROM_EMAIL=noreply@example.com    # Sender address
REPLY_HOSTNAME=loomio.example.com # Used in reply-to
SUPPORT_EMAIL=support@example.com # Support contact
HELPER_BOT_EMAIL=bot@example.com  # Bot notifications
```

### Port Selection

- **Port 587** - STARTTLS (recommended)
  ```bash
  SMTP_PORT=587
  SMTP_USE_TLS=true
  ```

- **Port 465** - SSL/TLS
  ```bash
  SMTP_PORT=465
  SMTP_USE_TLS=true
  ```

- **Port 25** - Unencrypted (NOT recommended)
  ```bash
  SMTP_PORT=25
  SMTP_USE_TLS=false
  ```

### Authentication Methods

Most providers use `plain`:
```bash
SMTP_AUTH=plain
```

Some may support:
- `login`
- `cram_md5`

Check your provider's documentation.

---

## Testing Email Configuration

### 1. Check Configuration in Rails Console

```bash
make rails-console
```

In the Rails console:
```ruby
# Check SMTP settings
ActionMailer::Base.smtp_settings

# Should show your configuration like:
# {:address=>"smtp.gmail.com", :port=>587, ...}
```

### 2. Send Test Email

```bash
make rails-console
```

```ruby
# Send test email
ActionMailer::Base.mail(
  from: ENV['FROM_EMAIL'],
  to: 'your-email@example.com',
  subject: 'Test from Loomio',
  body: 'If you receive this, SMTP is working!'
).deliver_now
```

If successful, you'll see:
```
Sent mail to your-email@example.com
```

### 3. Check Logs for Errors

```bash
make logs-app | grep -i smtp
```

Common errors:
- **Authentication failed** - Wrong username/password
- **Connection refused** - Wrong server/port
- **TLS error** - Wrong TLS setting

---

## Troubleshooting

### Email Not Sending

**Check 1: Verify SMTP settings in .env**
```bash
grep SMTP .env
```

**Check 2: Test connection**
```bash
# Install telnet if needed
sudo apt install telnet

# Test connection to SMTP server
telnet smtp.gmail.com 587
# Should connect. Type: QUIT to exit
```

**Check 3: Check Loomio logs**
```bash
make logs-app | grep -i "mail\|smtp"
```

### Authentication Errors

**Gmail:**
- Ensure 2FA is enabled
- Use App Password (not regular password)
- Allow less secure apps (if not using App Password)

**SendGrid:**
- Username must be exactly `apikey`
- Password is the full API key starting with `SG.`

**General:**
- Check for typos in username/password
- Verify SMTP credentials in provider dashboard

### TLS/SSL Errors

```bash
# Try switching TLS setting
SMTP_USE_TLS=true   # to false
SMTP_PORT=587       # to 465
```

### Connection Timeout

- Check firewall allows outbound port 587/465
- Verify SMTP_SERVER address is correct
- Try using IP address instead of hostname

### Emails Going to Spam

**Solutions:**
1. **Verify your domain** with the email provider
2. **Set up SPF record:**
   ```
   v=spf1 include:_spf.google.com ~all
   ```

3. **Set up DKIM** (provider-specific)

4. **Set up DMARC record:**
   ```
   v=DMARC1; p=none; rua=mailto:admin@example.com
   ```

5. **Use proper FROM email** (matches your domain)

### Rate Limiting

If you hit provider limits:

**Gmail:** 500/day
- Upgrade to Google Workspace
- Use multiple Gmail accounts

**SendGrid Free:** 100/day
- Upgrade to paid plan ($15/mo = 40k emails)

**Mailgun:** 5k/month (trial)
- Add payment method for higher limits

---

## Security Best Practices

### 1. Use App-Specific Passwords

Never use your main email password. Use:
- Gmail: App Passwords
- Other providers: API keys or app-specific passwords

### 2. Store Credentials Securely

```bash
# .env file should never be committed
cat .gitignore | grep .env
# Should show: .env

# Restrict permissions
chmod 600 .env
```

### 3. Use TLS Encryption

Always use:
```bash
SMTP_USE_TLS=true
SMTP_PORT=587  # or 465
```

### 4. Monitor Email Logs

```bash
# Check for unauthorized sending
make logs-app | grep "Sent mail"
```

### 5. Rotate Credentials

Change SMTP passwords every 90 days:

```bash
# Update in .env
nano .env

# Restart services
make restart
```

---

## DNS Configuration (Optional but Recommended)

To improve email deliverability, add these DNS records:

### SPF Record

```
Type: TXT
Name: @
Value: v=spf1 include:_spf.provider.com ~all
```

Replace `provider.com` with your email provider's SPF include.

### DKIM Record

Your email provider will give you a DKIM record. Add it as a TXT record.

### DMARC Record

```
Type: TXT
Name: _dmarc
Value: v=DMARC1; p=quarantine; rua=mailto:admin@example.com
```

### MX Record (for reply-by-email)

```
Type: MX
Name: @
Value: your-server-ip (or loomio.example.com)
Priority: 10
```

---

## Comparison Table

| Provider | Free Tier | Best For | Difficulty |
|----------|-----------|----------|------------|
| Gmail | 500/day | Personal use | ⭐ Easy |
| SendGrid | 100/day | Production | ⭐⭐ Medium |
| Mailgun | 5k/month* | Developers | ⭐⭐ Medium |
| AWS SES | Pay-per-use | Scale | ⭐⭐⭐ Hard |
| Mailtrap | Unlimited | Testing | ⭐ Easy |

*3 months trial

---

## Recommended Setup

**For Testing:**
1. Start with **Gmail** (easiest)
2. Or use **Mailtrap** (testing only)

**For Production:**
1. Use **SendGrid** (100 emails/day free)
2. Verify your domain
3. Set up SPF/DKIM/DMARC
4. Monitor deliverability

**For Scale:**
1. Use **AWS SES** ($0.10 per 1,000)
2. Or upgrade SendGrid plan
3. Implement proper DNS records
4. Set up bounce handling

---

## Quick Reference Commands

```bash
# Edit SMTP settings
nano .env

# Restart to apply changes
make restart

# Test SMTP in Rails console
make rails-console

# Check logs for email errors
make logs-app | grep -i smtp

# View all environment variables
docker compose config
```

---

## Need Help?

- Check provider documentation
- View Loomio logs: `make logs-app`
- Test in Rails console: `make rails-console`
- Ask in Loomio community: https://www.loomio.com/community

**Remember:** You do NOT need to run your own mail server! Use external SMTP services for best results. 📧
