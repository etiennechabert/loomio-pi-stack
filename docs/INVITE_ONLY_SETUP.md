# Invite-Only Setup Guide

Your Loomio instance is configured as a **private, invite-only community**. Public user registration is disabled - only administrators can create and invite users.

## 🚀 Quick Start

**For first-time setup:**

1. **Create your first admin account:**
   ```bash
   make add-admin
   ```
   Enter an email (can be fake like `admin@localhost`) and name. Save the displayed password.

2. **Log in to Loomio web interface** with the admin account

3. **Invite users from the web:**
   - Create a group
   - Click "Invite" button
   - Enter user email addresses
   - Add a welcome message
   - Click "Send invitations"

That's it! Users receive emails with password setup instructions and security guidelines.

---

## 🎯 Perfect Workflow

This setup implements your ideal onboarding flow:

1. **Admin enters email + name** (`make add-user`)
2. **User receives email** with password setup link (automatic)
3. **User sets own password** on first visit (forced)

✅ No manual password sharing
✅ No temporary passwords
✅ Secure token-based authentication
✅ User forced to create strong password

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

### 🌟 Recommended: Web-Based Invitation (Primary Method)

**This is the easiest and most user-friendly way to onboard users!**

Loomio has built-in web-based user invitation that's perfect for day-to-day user onboarding:

#### How to Invite Users from the Web Interface

1. **Log in as an admin** to your Loomio instance
2. **Navigate to a group** or create a new one
3. **Click the "Invite" button** in the Members panel
4. **Enter email addresses** of people you want to invite (one per line)
   - Email addresses can be for existing users OR new users
   - New user accounts are created automatically
5. **Add an optional personal message** to include in the invitation
6. **Click "Send invitations"**

#### What Happens Automatically

- ✅ Loomio creates user accounts for new email addresses
- ✅ Adds users as members to the selected group
- ✅ Sends invitation emails with your custom message
- ✅ Includes password setup instructions with security guidelines
- ✅ New users set their own secure passwords on first login

#### Benefits

- ✅ **No command-line access needed** - admins work from the web UI
- ✅ **Context-aware** - users are immediately added to the right group
- ✅ **Bulk invitations** - invite multiple users at once
- ✅ **Personalized messages** - add context for why they're being invited
- ✅ **Better UX** - intuitive interface for non-technical admins

---

### Alternative: Command-Line User Creation

For initial setup, automation, or when you need to create users without adding them to a group yet:

#### Method A: Makefile Command

```bash
# Create regular user
make add-user
# Prompts for: email and name
# System automatically sends password setup email

# Create admin user (displays password in console)
make add-admin
# Prompts for: email and name
# Displays password in console - no email sent
```

**Output for `make add-user`:**
```
✓ User Created Successfully!
✓ Password setup email sent to: user@example.com

Next steps:
  1. User checks email inbox
  2. User clicks 'Set Password' link
  3. User creates their own password
  4. User can now log in

Note: If email not received, check SMTP configuration
```

**Output for `make add-admin`:**
```
✓ Admin User Created Successfully!

Email:    admin@example.com
Password: Xy7$kP9mQ2nR8vL

⚠️  IMPORTANT: Save this password securely!
   This password will not be shown again.

Next steps:
  1. Log in at http://localhost:3000
  2. Change password after first login (recommended)
```

**Why different for admins?**
- Admin accounts are typically created with non-existent email addresses (e.g., `admin@localhost`)
- The password is displayed directly in the console for immediate use
- No email is sent since the email address may not be real
- After logging in, the admin can use the web interface to invite other users

**What happens:**
- Admin enters **only email + name**
- System creates account with random unusable password
- System sends **password reset email** automatically (with security recommendations)
- User receives email with:
  - Secure token link to set password
  - **Security guidelines** emphasizing NOT reusing passwords
  - Password best practices (16+ chars, passphrases, etc.)
  - Explanation of why unique passwords matter for self-hosted platforms
- User clicks link and **sets their own password**
- User is **forced to create password** (can't skip)

📧 **Email template:** The password setup email includes comprehensive security guidance. See `custom-views/devise/mailer/reset_password_instructions.html.erb` for details.

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

### Step 2: User Receives Email

The user automatically receives an email with subject: **"Reset password instructions"**

**Email contains:**
- Personalized greeting
- Link to set password (with secure token)
- **⚠️ Security guidelines section** with:
  - **Emphasis on NOT reusing passwords from other platforms**
  - Recommendation to use 16+ character passwords
  - Passphrase examples (e.g., "correct-horse-battery-staple")
  - Explanation of why unique passwords matter for self-hosted infrastructure
- Link expires in 6 hours for security
- No temporary password to share

**No admin action needed** - email is sent automatically with all security guidance included!

### Step 3: User Sets Password

1. User clicks "Set Password" link in email
2. Arrives at password creation page
3. Enters new password (must meet requirements)
4. Confirms password
5. **Automatically logged in** after setting password

**Security benefits:**
- ✅ User creates their own secure password
- ✅ No temporary password to share/leak
- ✅ Token-based, expires automatically
- ✅ User forced to set password (cannot skip)

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

**⚠️ IMPORTANT: SMTP is REQUIRED for this workflow to work.**

The automated email workflow sends password setup emails. Without SMTP:
- ✅ User accounts are created
- ❌ But emails are NOT sent
- ❌ Users cannot set passwords
- ❌ Manual password reset required

### Check SMTP Status

```bash
# Check if SMTP is configured
grep SMTP_ .env

# Should see:
# SMTP_DOMAIN=smtp.gmail.com
# SMTP_SERVER=smtp.gmail.com
# SMTP_PORT=587
# SMTP_USERNAME=your-email@gmail.com
# SMTP_PASSWORD=your-app-password
```

### Quick Test

```bash
# Test email sending
docker compose run --rm app rails runner "
  user = User.last
  user.send_reset_password_instructions
  puts 'Email sent!'
"
```

### Configure SMTP

**Required before using add-user/add-admin!**

See [SMTP_SETUP.md](../SMTP_SETUP.md) for detailed setup instructions.

### Fallback (if SMTP not configured)

If SMTP is not set up yet, you can manually set passwords:

```bash
# Create user
make add-user
# Enter email and name
# Email will fail but user is created

# Manually set password
docker compose run --rm app rails runner "
  user = User.find_by(email: 'user@example.com')
  password = 'SecurePassword123'
  user.update(password: password, password_confirmation: password)
  puts \"Password set to: #{password}\"
"

# Share password securely with user
```

---

## Security Best Practices

### 1. Password Security

#### Current Password Requirements

Loomio enforces the following password rules:

- **Minimum length**: 8 characters (enforced)
- **Maximum length**: 128 characters
- **Complexity**: None (⚠️ security concern)
- **Password storage**: bcrypt with 10 rounds (secure)

⚠️ **Security Warning**: Loomio currently does NOT enforce password complexity. Users can set weak passwords like:
- `password` (8 chars) - ✗ ACCEPTED
- `12345678` (8 chars) - ✗ ACCEPTED
- `qwerty123` (9 chars) - ✗ ACCEPTED

This is a **security concern** in invite-only mode where admins trust users to create secure passwords via the automated email workflow.

#### Recommended Password Practices

When onboarding users via `make add-user`:

**What the system does automatically:**
- ✅ Generates random unusable password for initial account creation
- ✅ Sends password reset email (token-based, expires in 6 hours)
- ✅ Forces user to create their own password
- ✅ Stores password securely using bcrypt

**What users should do:**
- ✅ Use minimum **16+ characters** (not just the 8 character minimum)
- ✅ Use passphrases like `correct-horse-battery-staple` (easy to remember, hard to crack)
- ✅ Mix uppercase, lowercase, numbers, and symbols
- ✅ Avoid common passwords, dictionary words, personal information
- ❌ Don't reuse passwords from other sites
- ❌ Don't use simple patterns like `Password123`

✅ **Good news:** Password security guidance is **automatically included** in the password setup email!

The custom email template (`custom-views/devise/mailer/reset_password_instructions.html.erb`) contains:
- Clear warning NOT to reuse passwords from other platforms
- Recommendation for 16+ character passwords
- Passphrase examples
- Explanation of why this matters for self-hosted infrastructure

**No manual communication needed** - users receive comprehensive security guidance automatically when you run `make add-user`.

#### Password Strength Improvements (Optional)

If you need stronger password enforcement, consider these options:

**Option 1: Client-side password strength meter**
Add a JavaScript library (like zxcvbn) to the password reset page to show strength feedback without changing server validation.

**Option 2: Custom password validation**
Add a custom validator to Loomio's User model to enforce complexity:

```ruby
# app/models/user.rb
validate :password_complexity

def password_complexity
  return if password.blank?

  unless password.match?(/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)/)
    errors.add :password, 'must include at least one lowercase letter, one uppercase letter, and one digit'
  end
end
```

**Option 3: Reject common passwords**
Use a gem like `pwned` to check passwords against known breach databases.

**Trade-offs:**
- ✅ Stronger security
- ❌ More complex onboarding
- ❌ May frustrate non-technical users
- ❌ Requires code changes and testing

For most private communities, **educating users** about password best practices is sufficient.

### 2. Secure Communication

**Note**: With the automated email workflow (`make add-user`), you NO LONGER need to manually share passwords! Users receive password setup links via email.

If you need to share other sensitive information:
- ✅ Use encrypted channels (password manager links, Signal, encrypted email)
- ❌ Don't send via plain text email or chat
- ❌ Don't write on paper or whiteboards

### 3. Regular Audits

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

### Onboarding New Team Member (Recommended Approach)

**Using Web Interface (Easiest):**

1. **Log in as admin** to Loomio
2. **Navigate to the group** the user should join
3. **Click "Invite"** button
4. **Enter email**: `newuser@company.com`
5. **Add optional message**: "Welcome to the team! Here you can..."
6. **Click "Send invitations"**

**What happens:**
- ✅ User account created automatically (if doesn't exist)
- ✅ User added to group
- ✅ User receives invitation email with:
  - Your personal message
  - Password setup link with security guidelines
  - Context about the group they're joining

**Timeline:**
- Admin: 30 seconds (via web UI)
- User: 2 minutes (check email, set password, login)
- Total: 2.5 minutes from invitation to active group member

---

### Alternative: Command-Line Approach

If you need to create a user without immediately adding them to a group:

```bash
# 1. Create user account
make add-user
# Enter: newuser@company.com, New User Name
# System automatically sends password setup email

# 2. User receives email
# User clicks link and sets their own password

# 3. Later: Add to groups via web interface
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
