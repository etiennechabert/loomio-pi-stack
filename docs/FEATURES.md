# Loomio Features & Configuration Guide

Complete guide to enabling and configuring Loomio features, including languages, translation, and optional functionality.

## Table of Contents
- [Language Support](#language-support)
- [Content Translation](#content-translation)
- [Feature Flags](#feature-flags)
- [Single Sign-On (SSO)](#single-sign-on-sso)
- [Theming & Branding](#theming--branding)
- [File Storage](#file-storage)
- [Performance Tuning](#performance-tuning)
- [Advanced Features](#advanced-features)

---

## Language Support

### Supported Languages

Loomio supports **40+ languages** out of the box, including:

| Language | Code | Language | Code |
|----------|------|----------|------|
| English | en | German | de |
| French | fr | Spanish | es |
| Italian | it | Portuguese | pt |
| Dutch | nl | Polish | pl |
| Russian | ru | Japanese | ja |
| Chinese (Simplified) | zh | Chinese (Traditional) | zh-TW |
| Korean | ko | Arabic | ar |
| Turkish | tr | Swedish | sv |
| Norwegian | no | Danish | da |
| Finnish | fi | Czech | cs |
| Hungarian | hu | Romanian | ro |
| Greek | el | Hebrew | he |
| Indonesian | id | Vietnamese | vi |
| Thai | th | Hindi | hi |

And many more!

### How Language Selection Works

**1. Automatic Detection**
When a user first visits your Loomio instance, it automatically detects their browser's preferred language and displays the interface in that language (if supported).

**2. User Preference**
Each user can change their language preference:
- Click on their profile picture
- Select "Edit profile"
- Choose preferred language from dropdown
- Save changes

**3. No System-Wide Default**
⚠️ **Important:** You cannot set a system-wide default language via environment variables. Each user controls their own language preference.

### Example: English & German Setup

For a German organization:

1. **Default behavior**: Users with German browsers see German automatically
2. **Manual selection**: Users can switch to German from profile settings
3. **No config needed**: Both languages are already supported!

---

## Content Translation

### Overview

Loomio includes **automatic content translation** powered by Google Translate. This allows users to read discussions and comments in their preferred language, even when posted in another language.

### How It Works

1. **Automatic Detection**: When content is in a different language than the user's preference
2. **Translate Button**: A "translate" button appears below the content
3. **On-Demand**: Translation happens only when user clicks the button
4. **Cached**: Translations are cached for performance

### Translation Providers

#### Option 1: Google Translate (Default)

**Setup:**

1. **Create Google Cloud Project**
   - Go to https://console.cloud.google.com/
   - Create new project or select existing

2. **Enable Translation API**
   - Go to "APIs & Services" → "Library"
   - Search for "Cloud Translation API"
   - Click "Enable"

3. **Create API Key**
   - Go to "APIs & Services" → "Credentials"
   - Click "Create Credentials" → "API Key"
   - Copy the key

4. **Configure Loomio**
   ```bash
   # In .env file
   GOOGLE_TRANSLATE_API_KEY=your-api-key-here
   ```

5. **Restart services**
   ```bash
   make restart
   ```

**Pricing:**
- Free tier: $10 credit per month (~500,000 characters)
- Paid: $20 per million characters
- See: https://cloud.google.com/translate/pricing

**Pros:**
- ✅ Simple setup
- ✅ Supports 100+ languages
- ✅ Good quality
- ✅ Free tier available

**Cons:**
- ❌ Quality varies by language pair
- ❌ May require billing account

---

#### Option 2: DeepL (Higher Quality)

**Setup:**

1. **Sign up for DeepL API**
   - Go to https://www.deepl.com/pro-api
   - Choose plan (Free or Pro)

2. **Get API Key**
   - Copy your authentication key from account dashboard

3. **Configure Loomio**
   ```bash
   # In .env file
   DEEPL_API_KEY=your-deepl-auth-key
   ```

4. **Restart services**
   ```bash
   make restart
   ```

**Pricing:**
- Free tier: 500,000 characters/month
- Pro: Starting at €5.49/month for 1M characters
- See: https://www.deepl.com/pro-api

**Pros:**
- ✅ Higher quality translations
- ✅ Better with European languages (especially German!)
- ✅ Natural-sounding output
- ✅ Free tier available

**Cons:**
- ❌ Fewer languages than Google (30 languages)
- ❌ Requires separate account

**Supported Languages:**
- **German** ✓ (excellent quality!)
- **English** ✓
- French, Spanish, Italian, Portuguese, Dutch, Polish, Russian, Japanese, Chinese, and more

**Recommended for German/English:** DeepL provides superior quality for German ↔ English translations!

---

### Testing Translation

**1. Enable translation API** (add key to .env)

**2. Restart Loomio**
```bash
make restart
```

**3. Create test content**
- Sign in as a user with English preference
- Post a message in German
- Sign in as another user (or switch language to German)
- You should see "translate" button

**4. Check logs**
```bash
make logs-app | grep -i translate
```

---

## Feature Flags

Loomio uses environment variables to enable/disable features.

### Available Feature Flags

**In `.env` file:**

```bash
# =============================================================================
# FEATURE FLAGS
# =============================================================================

# Disable public groups (make all groups private)
FEATURES_DISABLE_PUBLIC_THREADS=true

# Disable email/password login (SSO only)
FEATURES_DISABLE_EMAIL_LOGIN=true

# Disable built-in help system
FEATURES_DISABLE_HELP=true

# Disable user registration (invite-only)
# FEATURES_DISABLE_SIGNUP=true

# Disable group creation by users
# FEATURES_DISABLE_GROUP_CREATION=true
```

### Common Scenarios

#### Scenario 1: Private Organization (No Public Groups)

```bash
FEATURES_DISABLE_PUBLIC_THREADS=true
FEATURES_DISABLE_SIGNUP=true
```

Result: All groups are private, users must be invited

---

#### Scenario 2: SSO-Only Organization

```bash
FEATURES_DISABLE_EMAIL_LOGIN=true
# Plus configure your SSO (see SSO section)
```

Result: Users can only log in via SSO (Google, SAML, etc.)

---

#### Scenario 3: Controlled Group Creation

```bash
FEATURES_DISABLE_GROUP_CREATION=true
```

Result: Only admins can create groups

---

## Single Sign-On (SSO)

Loomio supports multiple SSO providers.

### Supported Providers

- Google OAuth
- Microsoft Azure AD
- SAML 2.0 (Okta, OneLogin, etc.)
- Generic OAuth2
- LDAP

### Google OAuth Setup

**1. Create OAuth Credentials**

Go to https://console.cloud.google.com/apis/credentials

**2. Configure OAuth Consent Screen**
- Application name: "Your Org Loomio"
- Authorized domains: your-domain.com

**3. Create OAuth Client ID**
- Application type: Web application
- Authorized redirect URIs: `https://loomio.your-domain.com/oauth/google/callback`

**4. Configure in `.env`:**

```bash
# Google OAuth
GOOGLE_OAUTH_APP_ID=your-client-id.apps.googleusercontent.com
GOOGLE_OAUTH_APP_SECRET=your-client-secret

# Optional: Restrict to specific domain
GOOGLE_OAUTH_ALLOWED_DOMAINS=your-company.com
```

**5. Restart and test:**

```bash
make restart
```

Users will see "Sign in with Google" button

---

### SAML SSO Setup

**Configure in `.env`:**

```bash
# SAML Configuration
SAML_IDP_ENTITY_ID=https://your-idp.com/entity-id
SAML_IDP_SSO_TARGET_URL=https://your-idp.com/sso
SAML_IDP_CERT_FINGERPRINT=AA:BB:CC:DD:EE:FF:...
SAML_ASSERTION_CONSUMER_SERVICE_URL=https://loomio.your-domain.com/saml/acs

# Optional
SAML_ISSUER=https://loomio.your-domain.com
```

---

## Theming & Branding

Customize Loomio's appearance to match your organization.

### Theme Configuration

**In `.env` file:**

```bash
# =============================================================================
# THEME AND CUSTOMIZATION
# =============================================================================

# Primary color (hex code without #)
THEME_PRIMARY_COLOR=1976d2

# Custom app name
THEME_APP_NAME=Our Organization

# Custom logo URL (publicly accessible)
THEME_LOGO_URL=https://your-domain.com/logo.png

# Favicon URL
# THEME_FAVICON_URL=https://your-domain.com/favicon.ico
```

### Color Examples

```bash
# Blue (professional)
THEME_PRIMARY_COLOR=1976d2

# Green (eco-friendly)
THEME_PRIMARY_COLOR=4caf50

# Purple (creative)
THEME_PRIMARY_COLOR=9c27b0

# Orange (energetic)
THEME_PRIMARY_COLOR=ff9800

# Red (bold)
THEME_PRIMARY_COLOR=f44336
```

### Logo Requirements

- Format: PNG, SVG, or JPG
- Recommended size: 200x50px (or similar ratio)
- Transparent background preferred
- Hosted on publicly accessible URL

**Example:**

```bash
THEME_LOGO_URL=https://example.com/images/logo.png
THEME_APP_NAME=Acme Corporation
THEME_PRIMARY_COLOR=ff6600
```

Restart: `make restart`

---

## File Storage

Configure where Loomio stores uploaded files.

### Option 1: Local Storage (Default)

Files stored in Docker volumes. Backed up automatically by backup service.

**No configuration needed!**

---

### Option 2: AWS S3

**Configure in `.env`:**

```bash
# =============================================================================
# FILE STORAGE (Optional)
# =============================================================================

# S3-compatible storage
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1
AWS_BUCKET=your-loomio-files

# Optional: Custom S3 endpoint (for S3-compatible services)
# AWS_ENDPOINT=https://s3.your-provider.com

# Optional: CloudFront CDN
# AWS_CLOUDFRONT_URL=https://d1234567890.cloudfront.net
```

**Benefits:**
- ✅ Scalable storage
- ✅ Separate from server
- ✅ CDN support
- ✅ Better for large deployments

---

### Option 3: DigitalOcean Spaces

```bash
AWS_ACCESS_KEY_ID=your-spaces-key
AWS_SECRET_ACCESS_KEY=your-spaces-secret
AWS_REGION=nyc3
AWS_BUCKET=your-space-name
AWS_ENDPOINT=https://nyc3.digitaloceanspaces.com
```

---

## Performance Tuning

Optimize Loomio for your hardware and load.

### Raspberry Pi 4 (4GB RAM)

```bash
# Recommended settings
PUMA_WORKERS=2
RAILS_MAX_THREADS=5
SIDEKIQ_CONCURRENCY=5
```

---

### Raspberry Pi 4 (8GB RAM)

```bash
# Better performance
PUMA_WORKERS=3
RAILS_MAX_THREADS=8
SIDEKIQ_CONCURRENCY=10
```

---

### Server (16GB+ RAM)

```bash
# High performance
PUMA_WORKERS=4
RAILS_MAX_THREADS=10
SIDEKIQ_CONCURRENCY=20
```

---

### Explanation

**PUMA_WORKERS**: Number of app processes
- More workers = handle more concurrent users
- Each worker uses ~300-500MB RAM
- Raspberry Pi: Keep at 2-3

**RAILS_MAX_THREADS**: Threads per worker
- More threads = handle more requests per worker
- Diminishing returns after 10-15

**SIDEKIQ_CONCURRENCY**: Background job threads
- More = faster email sending, notifications
- Increase if email/notifications are slow

---

## Advanced Features

### Webhooks

Send notifications to external services.

```bash
# Slack webhook
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL

# Custom webhook
WEBHOOK_URL=https://your-server.com/loomio-webhook
```

---

### Analytics

```bash
# Google Analytics
GOOGLE_ANALYTICS_ID=UA-XXXXXXXXX-X

# Matomo/Piwik
MATOMO_URL=https://analytics.your-domain.com
MATOMO_SITE_ID=1
```

---

### Error Tracking

```bash
# Sentry error tracking
SENTRY_DSN=https://public@sentry.io/project-id
```

---

### Custom CSS

Add custom styling:

```bash
CUSTOM_CSS_URL=https://your-domain.com/custom.css
```

---

### Email Customization

```bash
# Custom email sender name
HELPER_BOT_EMAIL_NAME=Your Organization Bot

# Email footer text
EMAIL_FOOTER_TEXT=© 2024 Your Organization

# Reply-to email
REPLY_TO_EMAIL=support@your-domain.com
```

---

## Configuration Examples

### Example 1: German/English Organization with Auto-Translation

```bash
# .env configuration

# No language config needed - users choose their preference!
# Both German and English are already supported

# Enable high-quality translation (DeepL recommended for German)
DEEPL_API_KEY=your-deepl-key

# Branding
THEME_APP_NAME=Unser Team
THEME_PRIMARY_COLOR=0066cc
THEME_LOGO_URL=https://example.com/logo.png

# Features
FEATURES_DISABLE_PUBLIC_THREADS=true  # Private organization
FEATURES_DISABLE_SIGNUP=true          # Invite-only
```

**Result:**
- German and English users each see interface in their language
- Content translation available with DeepL
- Private, branded instance

---

### Example 2: Public Community

```bash
# Open community settings

# Allow public groups
FEATURES_DISABLE_PUBLIC_THREADS=false

# Allow signups
# FEATURES_DISABLE_SIGNUP is not set

# Translation for international community
GOOGLE_TRANSLATE_API_KEY=your-google-key

# Simple branding
THEME_APP_NAME=Our Community
THEME_PRIMARY_COLOR=4caf50
```

---

### Example 3: Enterprise with SSO

```bash
# Enterprise configuration

# SSO only
FEATURES_DISABLE_EMAIL_LOGIN=true
GOOGLE_OAUTH_APP_ID=your-client-id
GOOGLE_OAUTH_APP_SECRET=your-secret
GOOGLE_OAUTH_ALLOWED_DOMAINS=company.com

# S3 storage
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_BUCKET=company-loomio

# Performance
PUMA_WORKERS=4
SIDEKIQ_CONCURRENCY=20

# Monitoring
SENTRY_DSN=https://...
```

---

## Testing Features

### Test Translation

```bash
# 1. Add API key to .env
nano .env
# Add: DEEPL_API_KEY=your-key

# 2. Restart
make restart

# 3. Test
# - Post in German
# - Switch user language to English
# - Click "translate" button
```

---

### Test Theming

```bash
# 1. Configure theme
nano .env
# Add:
# THEME_APP_NAME=Test Org
# THEME_PRIMARY_COLOR=ff6600

# 2. Restart
make restart

# 3. Check web interface
# - See custom name in header
# - See orange color scheme
```

---

### Test Feature Flags

```bash
# 1. Disable public groups
nano .env
# Add: FEATURES_DISABLE_PUBLIC_THREADS=true

# 2. Restart
make restart

# 3. Verify
# - Try creating public group
# - Option should be disabled
```

---

## Troubleshooting

### Translation Not Working

**Check API key:**
```bash
grep TRANSLATE .env
```

**Check logs:**
```bash
make logs-app | grep -i translate
```

**Test API key manually:**
```bash
# Google Translate
curl "https://translation.googleapis.com/language/translate/v2?key=YOUR_KEY&q=hello&target=de"

# DeepL
curl -X POST "https://api.deepl.com/v2/translate" \
  -d "auth_key=YOUR_KEY" \
  -d "text=hello" \
  -d "target_lang=DE"
```

---

### Theme Not Applying

**Clear browser cache:**
- Hard refresh: Ctrl+Shift+R (Cmd+Shift+R on Mac)
- Or clear cache in browser settings

**Check configuration:**
```bash
docker compose config | grep THEME
```

**Restart services:**
```bash
make restart
```

---

### Feature Flag Not Working

**Verify syntax:**
```bash
grep FEATURES .env
```

Must be exact: `FEATURES_DISABLE_PUBLIC_THREADS=true`

**Restart required:**
```bash
make restart
```

---

## Quick Reference

```bash
# View all features
make help

# Edit configuration
nano .env

# Apply changes
make restart

# Check logs
make logs-app

# Test configuration
docker compose config

# Check what's set
docker compose config | grep -i feature
docker compose config | grep -i theme
```

---

## Summary

### ✅ Languages (German & English)
- **No configuration needed!** Both already supported
- Users choose language from profile
- Auto-detects browser language

### ✅ Translation
- Add API key (Google Translate or DeepL)
- DeepL recommended for German
- On-demand translation with "translate" button

### ✅ Features
- Use `FEATURES_DISABLE_*` flags
- Control public groups, signups, SSO, etc.
- Restart after changes

### ✅ Theming
- Customize colors, logo, app name
- Set in .env file
- Takes effect after restart

---

**Need help?** See other documentation:
- [QUICKSTART.md](QUICKSTART.md) - Setup guide
- [README.md](../README.md) - Overview
- [.env.example](../.env.example) - All options

---

**Loomio supports your multilingual, feature-rich collaboration needs!** 🌍🇩🇪🇬🇧
