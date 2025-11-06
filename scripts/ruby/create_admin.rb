#!/usr/bin/env ruby
# Create admin user with direct password output
# Usage: docker exec -it loomio-app bundle exec rails runner scripts/ruby/create_admin.rb [email] [name]

require 'securerandom'

def generate_password(length = 16)
  # Generate secure password with mix of chars
  chars = [
    ('A'..'Z').to_a,
    ('a'..'z').to_a,
    ('0'..'9').to_a,
    ['!', '@', '#', '$', '%', '^', '&', '*']
  ].flatten
  
  password = Array.new(length) { chars.sample }.join
  
  # Ensure at least one of each type
  password[0] = ('A'..'Z').to_a.sample
  password[1] = ('a'..'z').to_a.sample
  password[2] = ('0'..'9').to_a.sample
  password[3] = ['!', '@', '#', '$', '%', '^', '&', '*'].sample
  
  password.chars.shuffle.join
end

# Get arguments
email = ARGV[0]
name = ARGV[1]
password = ARGV[2] # Optional: provide custom password

# Validate inputs
if email.nil? || email.empty?
  STDERR.puts "ERROR: Email is required"
  STDERR.puts "Usage: rails runner scripts/ruby/create_admin.rb EMAIL NAME [PASSWORD]"
  exit 1
end

if name.nil? || name.empty?
  STDERR.puts "ERROR: Name is required"
  STDERR.puts "Usage: rails runner scripts/ruby/create_admin.rb EMAIL NAME [PASSWORD]"
  exit 1
end

# Generate password if not provided
password = generate_password if password.nil? || password.empty?

# Check if user already exists
if User.exists?(email: email)
  STDERR.puts "ERROR: User with email #{email} already exists"
  exit 1
end

# Create admin user
begin
  user = User.create!(
    email: email,
    name: name,
    password: password,
    password_confirmation: password,
    email_verified: true,
    is_admin: true
  )
  
  # Output success message and credentials
  puts ""
  puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  puts "✓ Admin user created successfully!"
  puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  puts ""
  puts "Email:    #{email}"
  puts "Name:     #{name}"
  puts "Password: #{password}"
  puts ""
  puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  puts "⚠  Save this password immediately!"
  puts "   It will not be shown again."
  puts "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  puts ""
  
rescue => e
  STDERR.puts "ERROR: Failed to create admin user"
  STDERR.puts e.message
  exit 1
end
