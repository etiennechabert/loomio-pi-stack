# Admin User Management Guide

Complete guide to creating and managing admin users in Loomio.

## Table of Contents
- [Overview](#overview)
- [Method 1: Auto-Create via Environment Variables](#method-1-auto-create-via-environment-variables)
- [Method 2: Interactive Creation](#method-2-interactive-creation)
- [Method 3: Web Signup + Promotion](#method-3-web-signup--promotion)
- [Method 4: Rails Console](#method-4-rails-console)
- [Managing Users](#managing-users)
- [Troubleshooting](#troubleshooting)

## Overview

There are four ways to create admin users in Loomio:

| Method | Use Case | Difficulty | Automated? |
|--------|----------|------------|------------|
| ENV Variables | Production deployments | ⭐ Easy | ✅ Yes |
| Interactive CLI | Manual setup | ⭐⭐ Medium | ❌ No |
| Web + Promote | Testing/Development | ⭐ Easy | ❌ No |
| Rails Console | Advanced users | ⭐⭐⭐ Hard | ❌ No |

---

## Method 1: Auto-Create via Environment Variables

**Best for:** Production deployments, automated setups, Docker Compose stacks

This method automatically creates an admin user on first startup if credentials are provided in the `.env` file.

### Setup

**1. Edit your `.env` file:**

```bash
nano .env
```

**2. Add admin credentials:**

```bash
# =============================================================================
# ADMIN USER (Optional - Auto-create on first startup)
# =============================================================================

# Automatically create an admin user on first startup
LOOMIO_ADMIN_EMAIL=admin@example.com
LOOMIO_ADMIN_PASSWORD=your-secure-password-here
LOOMIO_ADMIN_NAME=Admin User
```

**3. Initialize or restart:**

```bash
# For first-time setup
make first-time-setup

# Or if already running
make auto-create-admin
```

### How It Works

- Script runs automatically during `make first-time-setup`
- Checks if user with that email already exists
- If not, creates new user with admin privileges
- If exists, promotes them to admin (if not already)
- User is marked as email verified (no confirmation needed)

### Advantages

✅ Fully automated - no manual steps
✅ Works with CI/CD pipelines
✅ Consistent across deployments
✅ Credentials stored securely in `.env`
✅ Idempotent - safe to run multiple times

### Security Notes

⚠️ **Important:**
- Never commit `.env` file to version control
- Use strong passwords (20+ characters)
- Change default password after first login
- Restrict `.env` file permissions: `chmod 600 .env`

---

## Method 2: Interactive Creation

**Best for:** Manual setup, one-off admin creation

Create an admin user interactively via the command line.

### Usage

```bash
make create-admin
```

### Interactive Prompts

```
Email address: admin@example.com
Username: Admin User
Password: ********
Confirm password: ********
Creating admin user...
✓ Admin user created!
```

### Features

- Validates password confirmation
- Checks for required fields
- Creates user with email verified
- Automatically grants admin privileges
- Shows error if user already exists

### Example

```bash
$ make create-admin
Create Admin User

Email address: john@example.com
Username: John Doe
Password: (hidden)
Confirm password: (hidden)
Creating admin user...
Admin user created: john@example.com
✓ Admin user created!
```

---

## Method 3: Web Signup + Promotion

**Best for:** Testing, development, when you want to test email flow

This is the traditional method - user signs up through the web interface, then gets promoted to admin.

### Steps

**1. Start Loomio:**

```bash
make start
```

**2. Open web interface:**

```
http://your-server-ip:3000
```

**3. Sign up for an account**
- Click "Sign up"
- Fill in email, name, password
- Submit form
- Check email for confirmation link
- Click confirmation link

**4. Promote to admin:**

Choose one method:

**Option A: Promote last user**
```bash
make make-admin
```

**Option B: Promote specific user**
```bash
make promote-user
# Enter email when prompted
```

**Option C: List users first**
```bash
make list-users
make promote-user
```

### When to Use

- ✅ Testing email configuration
- ✅ Demonstrating signup flow
- ✅ Development environment
- ❌ Production (use Method 1 instead)

---

## Method 4: Rails Console

**Best for:** Advanced users, custom scenarios, troubleshooting

Create users directly via Rails console.

### Access Rails Console

```bash
make rails-console
```

### Create Admin User

In the Rails console:

```ruby
# Create new admin user
user = User.create!(
  email: 'admin@example.com',
  name: 'Admin User',
  password: 'your-secure-password',
  password_confirmation: 'your-secure-password',
  email_verified: true,
  is_admin: true
)

puts "Created admin: #{user.email}"
```

### Promote Existing User

```ruby
# Find user by email
user = User.find_by(email: 'user@example.com')

# Make them admin
user.update(is_admin: true)

puts "#{user.name} is now an admin"
```

### Verify Admin Status

```ruby
# List all admins
User.where(is_admin: true).each do |u|
  puts "#{u.email} - #{u.name}"
end
```

### Exit Console

```ruby
exit
```

---

## Managing Users

### List All Users

```bash
make list-users
```

Output:
```
Loomio Users:
✓ admin@example.com - Admin User [ADMIN]
✓ john@example.com - John Doe
✗ pending@example.com - Pending User
```

Legend:
- `✓` = Email verified
- `✗` = Email not verified
- `[ADMIN]` = Admin privileges

### Promote User to Admin

```bash
make promote-user
```

You'll be prompted for the email address.

### Demote Admin to Regular User

```bash
make rails-console
```

```ruby
user = User.find_by(email: 'user@example.com')
user.update(is_admin: false)
```

### Delete User

```bash
make rails-console
```

```ruby
user = User.find_by(email: 'user@example.com')
user.destroy
```

### Reset User Password

```bash
make rails-console
```

```ruby
user = User.find_by(email: 'user@example.com')
user.update(
  password: 'new-password',
  password_confirmation: 'new-password'
)
```

### Verify User Email Manually

```bash
make rails-console
```

```ruby
user = User.find_by(email: 'user@example.com')
user.update(email_verified: true)
```

---

## Troubleshooting

### Admin User Not Created

**Check environment variables:**
```bash
grep LOOMIO_ADMIN .env
```

Should show:
```
LOOMIO_ADMIN_EMAIL=admin@example.com
LOOMIO_ADMIN_PASSWORD=...
LOOMIO_ADMIN_NAME=Admin User
```

**Run creation manually:**
```bash
make auto-create-admin
```

**Check logs:**
```bash
make logs-app | grep -i admin
```

### "User already exists" Error

This is normal if you run the command multiple times. The user won't be created again.

**Check if user exists:**
```bash
make list-users
```

**Verify they're admin:**
```bash
make rails-console
```

```ruby
User.find_by(email: 'admin@example.com').is_admin?
# Should return: true
```

### Password Too Weak

Loomio requires passwords to be at least 8 characters.

**Use stronger password:**
- Minimum 20 characters
- Mix of letters, numbers, symbols
- Use password generator: `openssl rand -base64 32`

### Email Not Verified

If user can't log in, email might not be verified.

**Manually verify:**
```bash
make rails-console
```

```ruby
user = User.find_by(email: 'user@example.com')
user.update(email_verified: true)
```

### Multiple Admins

You can have multiple admin users.

**Create additional admins:**
```bash
make create-admin
# Enter different email
```

**Or promote existing users:**
```bash
make promote-user
```

### Can't Access Rails Console

**Check if app is running:**
```bash
make status
```

**If not running:**
```bash
make start
```

**Try again:**
```bash
make rails-console
```

### Permission Denied Errors

**Check .env permissions:**
```bash
ls -la .env
```

**Fix permissions:**
```bash
chmod 600 .env
```

---

## Best Practices

### Production

1. ✅ Use environment variables (Method 1)
2. ✅ Use strong, unique passwords
3. ✅ Don't commit credentials to git
4. ✅ Create multiple admins for redundancy
5. ✅ Change default password after first login
6. ✅ Use password manager for credentials

### Development

1. ✅ Use web signup + promotion (Method 3)
2. ✅ Test email flow with real SMTP
3. ✅ Use different credentials than production
4. ✅ Document admin credentials in team wiki

### Security

1. ✅ Store `.env` securely
2. ✅ Use `chmod 600 .env`
3. ✅ Rotate passwords every 90 days
4. ✅ Monitor admin actions in logs
5. ✅ Use 2FA if available (future feature)
6. ✅ Limit admin access to trusted users

---

## Quick Reference

```bash
# Auto-create from .env
make auto-create-admin

# Create admin interactively
make create-admin

# Promote last signup
make make-admin

# Promote specific user
make promote-user

# List all users
make list-users

# Rails console
make rails-console

# Check user status
make list-users | grep admin@example.com
```

---

## Examples

### Example 1: Automated Production Setup

```bash
# 1. Configure .env
cat >> .env <<EOF
LOOMIO_ADMIN_EMAIL=admin@company.com
LOOMIO_ADMIN_PASSWORD=$(openssl rand -base64 32)
LOOMIO_ADMIN_NAME=System Administrator
EOF

# 2. Run setup
make first-time-setup

# Admin is automatically created!
```

### Example 2: Create Multiple Admins

```bash
# First admin via .env
make auto-create-admin

# Additional admins interactively
make create-admin
# Email: admin2@example.com
# ...

make create-admin
# Email: admin3@example.com
# ...

# Verify
make list-users
```

### Example 3: Promote Existing User

```bash
# User signs up via web at http://your-ip:3000
# Then promote them:

make promote-user
# Email: newuser@example.com

# Or by last signup:
make make-admin
```

---

## Need Help?

- View logs: `make logs-app`
- Check status: `make status`
- List users: `make list-users`
- Rails console: `make rails-console`
- All commands: `make help`

---

**Remember:** Always use strong, unique passwords for admin accounts! 🔐
