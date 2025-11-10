# Admin User Management Guide

Complete guide to creating and managing admin users in Loomio.

## Table of Contents
- [Overview](#overview)
- [Method 1: Interactive Creation](#method-1-interactive-creation)
- [Method 2: Rails Console](#method-2-rails-console)
- [Managing Users](#managing-users)
- [Troubleshooting](#troubleshooting)

## Overview

There are two ways to create admin users in Loomio:

| Method | Use Case | Difficulty |
|--------|----------|------------|
| Interactive CLI | Quick admin creation | ⭐ Easy |
| Rails Console | Advanced operations | ⭐⭐⭐ Hard |

---

## Method 1: Interactive Creation

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

## Method 2: Rails Console

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

All user management operations require the Rails console:

```bash
make rails-console
```

### List All Users

```ruby
# List all users with admin status
User.all.each do |u|
  admin_badge = u.is_admin? ? '[ADMIN]' : ''
  verified = u.email_verified? ? '✓' : '✗'
  puts "#{verified} #{u.email} - #{u.name} #{admin_badge}"
end
```

### List Only Admins

```ruby
User.where(is_admin: true).each do |u|
  puts "#{u.email} - #{u.name}"
end
```

### Promote User to Admin

```ruby
user = User.find_by(email: 'user@example.com')
user.update(is_admin: true)
puts "#{user.name} is now an admin"
```

### Demote Admin to Regular User

```ruby
user = User.find_by(email: 'user@example.com')
user.update(is_admin: false)
puts "#{user.name} is no longer an admin"
```

### Delete User

```ruby
user = User.find_by(email: 'user@example.com')
user.destroy
puts "User deleted"
```

### Reset User Password

```ruby
user = User.find_by(email: 'user@example.com')
user.update(
  password: 'new-password',
  password_confirmation: 'new-password'
)
puts "Password updated for #{user.email}"
```

### Verify User Email Manually

```ruby
user = User.find_by(email: 'user@example.com')
user.update(email_verified: true)
puts "Email verified for #{user.email}"
```

---

## Troubleshooting

### "User already exists" Error

This is normal if you run `make create-admin` with an email that's already registered.

**Verify if user exists and is admin:**

```bash
make rails-console
```

```ruby
user = User.find_by(email: 'admin@example.com')
if user
  puts "User exists: #{user.email}"
  puts "Is admin: #{user.is_admin?}"
  puts "Email verified: #{user.email_verified?}"
else
  puts "User not found"
end
```

**To promote existing user to admin:**

```ruby
user = User.find_by(email: 'admin@example.com')
user.update(is_admin: true)
puts "#{user.name} is now an admin"
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
# Enter different email for each admin
```

**Or promote existing users via Rails console:**
```bash
make rails-console
```

```ruby
user = User.find_by(email: 'user@example.com')
user.update(is_admin: true)
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

---

## Best Practices

### Admin Creation

1. Use `make create-admin` for quick admin user creation
2. Use strong, unique passwords (20+ characters recommended)
3. Create multiple admins for redundancy
4. Document admin credentials securely (password manager recommended)

### User Management

1. Use Rails console for advanced operations
2. Always verify user exists before promoting/demoting
3. Be careful when deleting users - operation cannot be undone
4. Keep track of who has admin privileges

### Security

1. Use strong passwords (minimum 8 characters, 20+ recommended)
2. Limit admin access to trusted users only
3. Monitor admin actions in logs
4. Regularly audit admin user list

---

## Quick Reference

### Available Commands

```bash
# Create admin interactively
make create-admin

# Access Rails console for user management
make rails-console
```

### Common Rails Console Operations

```ruby
# List all users
User.all.each { |u| puts "#{u.email} - #{u.name} #{u.is_admin? ? '[ADMIN]' : ''}" }

# Promote user to admin
User.find_by(email: 'user@example.com').update(is_admin: true)

# List all admins
User.where(is_admin: true).pluck(:email, :name)

# Check if user is admin
User.find_by(email: 'user@example.com').is_admin?
```

---

## Examples

### Example 1: Create First Admin

```bash
# Create admin interactively
make create-admin

# Follow prompts:
# Email address: admin@example.com
# Username: Admin User
# Password: (enter secure password)
# Confirm password: (re-enter password)
```

### Example 2: Create Multiple Admins

```bash
# Create first admin
make create-admin
# Email: admin1@example.com

# Create second admin
make create-admin
# Email: admin2@example.com

# Verify both exist via Rails console
make rails-console
```

```ruby
User.where(is_admin: true).each do |u|
  puts "#{u.email} - #{u.name}"
end
exit
```

### Example 3: Promote Existing User to Admin

A user signs up through the web interface at `http://your-server-ip:3000`, then you promote them:

```bash
make rails-console
```

```ruby
# Find and promote the user
user = User.find_by(email: 'newuser@example.com')
user.update(is_admin: true)
puts "#{user.name} is now an admin"
exit
```

---

## Need Help?

- View logs: `make logs-app`
- Check status: `make status`
- Rails console: `make rails-console`
- All commands: `make help`
