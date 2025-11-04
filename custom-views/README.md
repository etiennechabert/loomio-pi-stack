# Custom Loomio Email Templates

This directory contains custom Devise email templates that override the default Loomio email content.

## Purpose

These custom templates are used to:
- Add security recommendations directly in user onboarding emails
- Emphasize the importance of unique passwords for self-hosted infrastructure
- Provide clear password creation guidelines

## Structure

```
custom-views/
└── devise/
    └── mailer/
        └── reset_password_instructions.html.erb
```

## How It Works

The `docker-compose.yml` mounts this directory into both the `app` and `worker` containers:

```yaml
volumes:
  - ./custom-views/devise:/loomio/app/views/devise:ro
```

This overrides Devise's default email templates with our custom versions.

## Custom Templates

### reset_password_instructions.html.erb

**When sent:**
- When admins invite users via the web interface (primary method)
- When admins run `make add-user` (command-line alternative)
- When users request a password reset (via "Forgot password?" link)

**Note:** The `make add-admin` command does NOT send this email - it displays the password directly in the console instead.

**Custom content:**
- Personalized greeting using user's name
- Clear call-to-action: "Set my password" link
- **⚠️ Security guidelines section** with emphasis on:
  - **NOT reusing passwords** (most important for self-hosted platforms)
  - Using 16+ character passwords
  - Passphrase recommendations
  - Complexity best practices
- Explanation of why unique passwords matter for self-hosted infrastructure
- Link expiration notice (6 hours)

## Modifying Templates

To modify the email content:

1. Edit the template file in `custom-views/devise/mailer/`
2. Restart the containers to apply changes:
   ```bash
   docker compose restart app worker
   ```

**Note:** Templates use ERB (Embedded Ruby) syntax. Available variables:
- `@resource` - The user object (has `.name` and `.email`)
- `@token` - The password reset token
- `edit_password_url()` - Rails helper to generate the reset URL

## Best Practices

- Keep emails concise but informative
- Always include security guidance for password creation
- Make the call-to-action button/link prominent
- Explain why security measures matter (build user understanding, not just compliance)
- Test emails after making changes

## Testing

To test the email template without actually sending emails:

```bash
# Preview the email in Rails console
docker compose run --rm app rails c
user = User.last
UserMailer.reset_password_instructions(user, 'fake-token').deliver_now
```

Or use a tool like [MailCatcher](https://mailcatcher.me/) to intercept and view test emails during development.
