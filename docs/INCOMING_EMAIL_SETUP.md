# Incoming Email Setup for Loomio (Reply-by-Email)

This guide explains how to enable **reply-by-email** functionality in Loomio using Cloudflare Email Routing and Email Workers.

## Overview

With this setup:
- ✅ Users can reply to Loomio notification emails
- ✅ Replies appear directly in discussions
- ✅ No additional email server needed
- ✅ No port 25 exposure
- ✅ Everything stays within Cloudflare
- ✅ Secure token-based authentication

## Security Model

This setup uses **token-based authentication**:

The Email Worker sends an `X-Email-Token` header that must match the `EMAIL_PROCESSOR_TOKEN` in your Loomio configuration.

This prevents:
- ❌ Unauthorized webhook flooding
- ❌ Email injection attacks
- ✅ Only verified Cloudflare Email Worker can send emails to Loomio

## Architecture

```
Incoming Email
    ↓
Cloudflare Email Routing (MX records)
    ↓
Cloudflare Email Worker
    ↓
HTTP POST to https://loomio.lyckbo.de/rails/action_mailbox/relay/inbound_emails
    ↓
Cloudflare Tunnel
    ↓
Loomio App ActionMailbox (Rails Mail library processes email)
```

## Prerequisites

- ✅ Cloudflare account with your domain (lyckbo.de)
- ✅ Cloudflare Tunnel configured
- ✅ Wrangler CLI installed (for deploying workers)

---

## Setup Steps

### Step 1: Add Email Worker Configuration to .env

1. Generate authentication token:
   ```bash
   openssl rand -hex 32
   ```

2. Add to your `.env` file:
   ```bash
   # Incoming Email (Reply-by-Email)
   EMAIL_PROCESSOR_TOKEN=YOUR_RANDOM_TOKEN
   ```

   The webhook URL (`/email_processor`) is automatically constructed from your `CANONICAL_HOST` during deployment.

### Step 2: Deploy the Email Worker

```bash
make deploy-email-worker
```

The script will:
- ✅ Validate configuration
- ✅ Deploy worker to Cloudflare
- ✅ Configure secrets
- ✅ Display next steps

**Save the EMAIL_PROCESSOR_TOKEN shown - you'll need it!**

### Step 3: Restart Loomio

Restart Loomio to apply the new configuration:
```bash
make restart
```

### Step 4: Add ActionMailbox Route to Cloudflare Tunnel

1. Go to **Cloudflare Dashboard** → **Zero Trust** → **Networks** → **Tunnels**
2. Select your tunnel (`loomio`)
3. Click **Configure**
4. Under **Public Hostname**, add a new route:
   - **Path**: `/rails/action_mailbox/relay/inbound_emails`
   - **Service**: `http://app:3000`
   - Click **Save**

**Note**: This route allows the Cloudflare Email Worker to send raw emails to Loomio's ActionMailbox relay ingress endpoint. Rails Mail library handles all email parsing automatically (MIME, attachments, encoding, etc.).

### Step 5: Enable Cloudflare Email Routing

1. Go to **Cloudflare Dashboard**
2. Select your domain: `lyckbo.de`
3. Navigate to **Email** → **Email Routing**
4. Click **Enable Email Routing**
5. Cloudflare will automatically configure DNS records:
   - MX records pointing to Cloudflare's email servers
   - SPF record for email verification

### Step 6: Configure Email Routing Rule

1. In **Cloudflare Dashboard** → **Email** → **Email Routing**
2. Go to **Routes** tab
3. Click **Create address**
4. Configure a catch-all route:
   - **Custom address**: `*@loomio.lyckbo.de` (catch-all)
   - **Action**: Send to Worker
   - **Worker**: Select `loomio-email-worker`
   - Click **Save**

**Alternative**: You can also create specific addresses like:
- `reply@loomio.lyckbo.de`
- `noreply@loomio.lyckbo.de`

### Step 7: Verify Loomio Configuration

Ensure your `.env` has:

```bash
CANONICAL_HOST=loomio.lyckbo.de
REPLY_HOSTNAME=loomio.lyckbo.de
FROM_EMAIL=loomiolyckbo@gmail.com
EMAIL_PROCESSOR_TOKEN=YOUR_TOKEN
```

---

## Testing

### Test 1: Check Email Routing

```bash
# Send a test email to any address @loomio.lyckbo.de
echo "Test email" | mail -s "Test" test@loomio.lyckbo.de
```

Check Worker logs:
```bash
wrangler tail loomio-email-worker
```

### Test 2: Reply to a Loomio Notification

1. Create a discussion or comment in Loomio
2. Wait for the notification email
3. **Reply to that email** from your email client
4. Check if your reply appears in the Loomio discussion

---

## Troubleshooting

### Worker Logs

View real-time logs:
```bash
wrangler tail loomio-email-worker
```

### Check Email Routing Status

1. **Cloudflare Dashboard** → **Email** → **Email Routing**
2. Check **Overview** for routing statistics
3. Check **Logs** tab for delivery details

### Common Issues

**Issue: Email not arriving**
- Check MX records are set correctly in DNS
- Verify Email Routing is enabled
- Check Worker logs for errors

**Issue: 404 error on webhook**
- Verify `/rails/action_mailbox/relay/inbound_emails` route exists in Cloudflare Tunnel
- Check tunnel is running and healthy
- Ensure Loomio is using ActionMailbox (should be default in recent versions)

**Issue: Loomio not processing email**
- Check Loomio app logs: `make logs-app | grep email`
- Verify `REPLY_HOSTNAME` is set correctly in .env

---

## How It Works

### 1. Email Arrives

When someone sends email to `anything@loomio.lyckbo.de`:
- Cloudflare's MX servers receive it
- Email Routing matches the catch-all rule
- Routes to Email Worker

### 2. Worker Processes

The Email Worker (`cloudflare/email-worker.js`):
- Receives raw email from Cloudflare Email Routing
- Sends complete raw email (RFC 822 format) as multipart/form-data
- Posts to ActionMailbox relay ingress: `https://loomio.lyckbo.de/rails/action_mailbox/relay/inbound_emails`

### 3. Loomio ActionMailbox Processes

The request goes through:
- Cloudflare Tunnel
- Loomio app container
- Rails ActionMailbox relay ingress

Rails Mail library automatically handles:
- **MIME parsing** - nested multipart/mixed and multipart/alternative structures
- **Encoding** - quoted-printable, base64, UTF-8, and other character encodings
- **Attachments** - extracts and stores file attachments
- **Inline images** - handles Content-ID (CID) references
- **Body extraction** - separates text/plain and text/html parts

`ReceivedEmailMailbox` then:
- Validates the email format
- Identifies the discussion/comment thread (via reply-to address)
- Posts the reply content to the correct thread

---

## Security Notes

✅ **No open ports** - All traffic through Cloudflare Tunnel
✅ **No email server** - Cloudflare handles SMTP
✅ **Encrypted transit** - HTTPS/TLS end-to-end
✅ **Spam filtering** - Cloudflare Email Security

---

## Costs

- **Cloudflare Email Routing**: Free (up to 100,000 emails/month)
- **Cloudflare Workers**: Free (first 100,000 requests/day)
- **Total**: $0/month for typical usage

---

## Maintenance

### Update Worker

```bash
wrangler deploy cloudflare-email-worker.js --name loomio-email-worker
```

### View Worker Metrics

1. **Cloudflare Dashboard** → **Workers & Pages**
2. Select `loomio-email-worker`
3. View **Metrics** tab

### Disable Reply-by-Email

To temporarily disable:
1. Go to **Email Routing** → **Routes**
2. Disable or delete the worker route
3. Or update `.env`:
   ```bash
   REPLY_HOSTNAME=gmail.com
   ```

---

## Alternative: Forward to Specific Email

If you want a backup, you can also forward emails to a regular inbox:

```bash
# Set fallback email
wrangler secret put FALLBACK_EMAIL --name loomio-email-worker
# Enter: your-backup@gmail.com
```

The worker will forward to both the webhook AND the fallback email.

---

## References

- [Cloudflare Email Routing Docs](https://developers.cloudflare.com/email-routing/)
- [Email Workers Documentation](https://developers.cloudflare.com/email-routing/email-workers/)
- [Wrangler CLI Reference](https://developers.cloudflare.com/workers/wrangler/)

---

**Need help?** Check the logs:
- Worker: `wrangler tail loomio-email-worker`
- Loomio: `make logs-app | grep email`
- Cloudflare Tunnel: `docker logs loomio-cloudflared`
