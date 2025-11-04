# Invite-Only Setup Guide

Your Loomio instance is configured as a **private, invite-only community**. Public user registration is disabled - only administrators can create and invite users.

## Configuration

The following settings are enabled in your `.env` files:

```bash
# Disable public registration
FEATURES_DISABLE_SIGNUP=true

# Disable public threads (users must login to view)
FEATURES_DISABLE_PUBLIC_THREADS=true
```

**Result**: Users cannot self-register. The signup page is hidden and signup attempts are rejected.

---

## User Onboarding Workflow

### Step 1: Admin Creates User Account

Admins have two methods to create users:

#### Method A: Makefile Command (Recommended)

```bash
# Create regular user
make add-user
# Follow prompts: enter email and name
# System generates secure password

# Create admin user
make add-admin
# Follow prompts: enter email and name
# System generates secure password
```

**Output:**
```
✓ User Created Successfully!

Credentials:
  Email:    user@example.com
  Name:     John Doe
  Password: aBc123XyZ456

⚠ IMPORTANT: Save this password securely!
   It will not be displayed again.
```

#### Method B: Rails Console (Advanced)

```bash
docker compose run --rm app rails c

# Create regular user
user = User.create!(
  email: 'user@example.com',
  name: 'John Doe',
  password: 'SecurePassword123',
  password_confirmation: 'SecurePassword123',
  email_verified: true,
  is_admin: false
)

# Create admin user
admin = User.create!(
  email: 'admin@example.com',
  name: 'Jane Admin',
  password: 'SecurePassword123',
  password_confirmation: 'SecurePassword123',
  email_verified: true,
  is_admin: true
)
```

### Step 2: Admin Shares Credentials

The admin securely shares the credentials with the new user:
- Email address
- Temporary password
- Login URL: `https://your-loomio-domain.com`

**Security best practice**: Use a password manager or encrypted communication channel.

### Step 3: User First Login

1. User navigates to the Loomio instance
2. Clicks "Sign In"
3. Enters provided email and password
4. **Important**: User should immediately change password:
   - Click profile icon → Account Settings → Change Password

---

## Group Invitations

Once a user account exists, admins can invite them to groups:

### Via Web Interface

1. Navigate to your group
2. Click "Members" or "Manage"
3. Click "Invite people"
4. Enter the user's email address (must match their account email)
5. Click "Send invitation"

### Via Email

Users will receive an invitation email with a link to join the group.

---

## Managing Users

### List All Users

```bash
make list-users
```

**Output:**
```
Loomio Users:
✓ admin@example.com - Jane Admin [ADMIN]
✓ user1@example.com - John Doe
✓ user2@example.com - Mary Smith
```

### Promote User to Admin

```bash
docker compose run --rm app rails runner "
  user = User.find_by(email: 'user@example.com')
  user.update(is_admin: true)
  puts 'User promoted to admin'
"
```

### Reset User Password

```bash
docker compose run --rm app rails runner "
  user = User.find_by(email: 'user@example.com')
  new_password = SecureRandom.base64(16)
  user.update(password: new_password, password_confirmation: new_password)
  puts \"Password reset to: #{new_password}\"
"
```

### Delete User

```bash
docker compose run --rm app rails runner "
  user = User.find_by(email: 'user@example.com')
  user.destroy
  puts 'User deleted'
"
```

---

## What Users See

### Signup Page Disabled

When `FEATURES_DISABLE_SIGNUP=true` is set:

- ❌ Signup links are hidden
- ❌ Signup page returns error: "Sign up is disabled"
- ❌ Direct signup attempts are rejected
- ✅ Only "Sign In" button is shown

### Login Page

Users see a standard login page with:
- Email field
- Password field
- "Forgot password?" link (for password resets)
- **No "Sign up" link**

---

## Email Configuration

For user invitations and password resets to work, SMTP must be configured.

### Check SMTP Status

```bash
# Check if SMTP is configured
grep SMTP_ .env
```

### Quick Test

```bash
# Send test email
docker compose run --rm app rails runner "
  UserMailer.test_email('your-email@example.com').deliver_now
"
```

### Configure SMTP

See [SMTP_SETUP.md](../SMTP_SETUP.md) for detailed setup instructions.

---

## Security Best Practices

### 1. Strong Passwords

When creating users:
- ✅ Use auto-generated passwords (via `make add-user`)
- ✅ Minimum 12 characters
- ✅ Mix of letters, numbers, symbols
- ❌ Don't reuse passwords

### 2. Secure Communication

When sharing credentials:
- ✅ Use encrypted channels (password manager links, Signal, encrypted email)
- ❌ Don't send via plain text email or chat
- ❌ Don't write on paper or whiteboards

### 3. Force Password Changes

Require users to change their temporary password on first login:

```bash
# Set password as expired
docker compose run --rm app rails runner "
  user = User.find_by(email: 'user@example.com')
  user.update(password_changed_at: 1.year.ago)
"
```

### 4. Regular Audits

```bash
# Check inactive users (no login in 90 days)
docker compose run --rm app rails runner "
  User.where('last_sign_in_at < ?', 90.days.ago).each do |user|
    puts \"#{user.email} - Last login: #{user.last_sign_in_at}\"
  end
"
```

---

## Common Workflows

### Onboarding New Team Member

```bash
# 1. Create user account
make add-user
# Enter: newuser@company.com, New User Name

# 2. Note the generated password
# Example output: Password: aBc123XyZ456

# 3. Share credentials securely
# Send via password manager or encrypted channel

# 4. Add to groups via web interface
# Navigate to group → Invite → newuser@company.com
```

### Offboarding Team Member

```bash
# 1. Remove from all groups (via web interface)
# Go to each group → Members → Remove user

# 2. Delete user account
docker compose run --rm app rails runner "
  user = User.find_by(email: 'olduser@company.com')
  user.destroy
  puts 'User removed'
"
```

### Temporary Access

```bash
# 1. Create user with expiration note
make add-user
# Enter: contractor@company.com, Contractor Name

# 2. Set reminder to remove after project
# Add to calendar or task manager

# 3. Remove when complete
docker compose run --rm app rails runner "
  User.find_by(email: 'contractor@company.com').destroy
"
```

---

## Troubleshooting

### Users Report "Signup Disabled" Error

**This is expected behavior.** Users cannot self-register. Admins must create accounts.

**Solution**: Admin creates account via `make add-user`, shares credentials.

### User Can't Reset Password

**Cause**: SMTP not configured

**Solution**: Configure email settings (see [SMTP_SETUP.md](../SMTP_SETUP.md))

**Workaround**: Admin resets password manually:

```bash
docker compose run --rm app rails runner "
  user = User.find_by(email: 'user@example.com')
  new_password = SecureRandom.base64(16)
  user.update(password: new_password, password_confirmation: new_password)
  puts \"New password: #{new_password}\"
"
```

### Admin Accidentally Deleted Own Account

**Prevention**: Keep at least 2 admin accounts

**Recovery** (if database backup available):

```bash
# Restore recent backup
make restore-db

# Or create new admin from scratch
make add-admin
```

### Need to Re-Enable Public Signup (Testing)

**Temporarily enable**:

```bash
# 1. Edit .env
nano .env

# 2. Comment out or remove:
# FEATURES_DISABLE_SIGNUP=true

# 3. Restart services
docker compose restart app worker

# 4. Re-enable when done:
# Uncomment FEATURES_DISABLE_SIGNUP=true
# Restart services
```

---

## Alternative: Email Domain Restrictions

If you want to allow signups but only from your organization:

```bash
# In .env, instead of FEATURES_DISABLE_SIGNUP:
GOOGLE_OAUTH_ALLOWED_DOMAINS=your-company.com
SAML_ALLOWED_DOMAINS=your-company.com
```

This allows self-registration but only from allowed email domains.

**See**: [OAUTH2_SETUP.md](../OAUTH2_SETUP.md) for SSO configuration.

---

## Summary

Your Loomio instance is configured for **maximum privacy and control**:

✅ **Private community** - No public access
✅ **Invite-only** - Admins control all user accounts
✅ **No self-registration** - Users cannot sign up themselves
✅ **Admin-managed onboarding** - Controlled user creation and invitation

This setup is ideal for:
- Private organizations
- Internal corporate communities
- Closed user groups
- Sensitive or confidential discussions

For public or semi-public communities, see [FEATURES.md](../FEATURES.md) for other configuration options.
