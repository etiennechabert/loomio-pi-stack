#!/usr/bin/env ruby
# Create admin user and generate password reset token

email = ARGV[0]
name = ARGV[1]

if email.nil? || name.nil?
  puts "ERROR: Email and name required"
  exit 1
end

# Generate temporary password
temp_pass = SecureRandom.hex(32)

# Create user
user = User.create!(
  email: email,
  name: name,
  password: temp_pass,
  password_confirmation: temp_pass,
  email_verified: true,
  is_admin: true
)

# Generate password reset token
raw_token, hashed_token = Devise.token_generator.generate(User, :reset_password_token)
user.reset_password_token = hashed_token
user.reset_password_sent_at = Time.now
user.save!(validate: false)

# Output only the token (for capture)
puts raw_token
