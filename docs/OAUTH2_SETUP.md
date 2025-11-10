# Google Drive OAuth2 Setup for Loomio Pi Stack

This guide walks you through setting up OAuth2 authentication for Google Drive instead of Service Account credentials. OAuth2 removes the file creation limitations imposed by Service Accounts.

## Why OAuth2 Instead of Service Account?

- **Service Account**: Limited to creating a certain number of files per day (~10,000)
- **OAuth2**: No file creation limits - perfect for backing up many files

## Prerequisites

- Raspberry Pi with Loomio running at 192.168.0.229
- SSH access to the Pi
- Google account: lyckboloomio@gmail.com
- Google Drive folder ID where backups will be stored

## Step 1: SSH into Your Raspberry Pi

```bash
ssh echabert@192.168.0.229
cd /home/echabert/loomio-pi-stack
```

## Step 2: Ensure Backup Container is Running

```bash
docker compose up -d backup
```

## Step 3: Generate OAuth2 Token

Run this command inside the backup container:

```bash
docker compose exec backup rclone authorize "drive"
```

This command will output a URL that looks like:

```
If your browser doesn't open automatically go to the following link: https://accounts.google.com/o/oauth2/auth?...
Log in and authorize rclone for access
Waiting for code...
```

### Option A: On Raspberry Pi Desktop

If you're running this on the Pi with a desktop environment:
1. The browser will open automatically
2. Log in with `lyckboloomio@gmail.com`
3. Authorize the application
4. The terminal will display the token

### Option B: On Headless Raspberry Pi (No Browser)

If the Pi is headless (no desktop), you need to generate the token on another computer:

1. **On your Mac/PC**, install rclone:
   ```bash
   # macOS
   brew install rclone

   # Or download from https://rclone.org/downloads/
   ```

2. **Generate the token on your computer**:
   ```bash
   rclone authorize "drive"
   ```

3. **Browser opens automatically**:
   - Log in with `lyckboloomio@gmail.com`
   - Click "Allow" to grant permissions

4. **Copy the token** from the terminal output. It looks like:
   ```
   Paste the following into your remote machine --->
   {"access_token":"ya29.a0...","token_type":"Bearer","refresh_token":"1//0g...","expiry":"2024-12-31T23:59:59.999Z"}
   <---End paste
   ```

5. **Return to Raspberry Pi** and save this token for the next step

## Step 4: Add Token to .env File

On the Raspberry Pi, edit your .env file:

```bash
nano .env
```

Find the Google Drive section and update it:

```bash
# Google Drive Integration
GDRIVE_ENABLED=true
GDRIVE_TOKEN='{"access_token":"ya29.a0AfB_...","token_type":"Bearer","refresh_token":"1//0gXqP...","expiry":"2024-12-31T23:59:59.999Z"}'
GDRIVE_FOLDER_ID=your_folder_id_here
```

**Important Notes:**
- Keep the single quotes around the JSON token: `GDRIVE_TOKEN='...'`
- The token is a single-line JSON object
- Don't break it across multiple lines

## Step 5: Restart Services

Restart the backup service to use the new OAuth2 token:

```bash
docker compose restart backup
```

Check the logs to verify it's working:

```bash
docker compose logs -f backup
```

You should see successful Google Drive sync messages.

## Step 6: Test the Configuration

Manually trigger a backup to test:

```bash
# Create a test backup
docker compose exec backup bash -c "/app/backup-and-sync.sh"
```

Watch the output - you should see:
```
Syncing data to Google Drive...
Syncing database backups...
Transferred: ... / ... , 100%
✓ Data sync completed
```

## Token Structure Explained

The OAuth2 token is a JSON object with these fields:

```json
{
  "access_token": "ya29.a0...",     // Short-lived access token
  "token_type": "Bearer",            // Always "Bearer"
  "refresh_token": "1//0g...",       // Used to get new access tokens
  "expiry": "2024-12-31T23:59:59Z"   // When access token expires
}
```

**Important**: The `refresh_token` is the most critical part. It allows rclone to automatically get new access tokens when the current one expires. Never share this token!

## Troubleshooting

### Error: "token: missing required scope"

Your token doesn't have the right permissions. Re-run `rclone authorize "drive"` and make sure to grant all requested permissions.

### Error: "Failed to create file system"

Check that:
1. `GDRIVE_TOKEN` is properly set in .env (with single quotes)
2. `GDRIVE_FOLDER_ID` is correct
3. The Google account has access to the folder

### Error: "unauthorized_client"

The OAuth2 app configuration might be incorrect. Make sure you're using the correct client credentials.

### Token Expired

Don't worry! If you see:
```
Failed to configure token: oauth2: token expired and refresh token is not set
```

This shouldn't happen if you have a valid `refresh_token`. If it does:
1. Re-generate the token with `rclone authorize "drive"`
2. Update `.env` with the new token
3. Restart: `docker compose restart backup`

## Verification

After setup, verify everything works:

```bash
# Check backup service logs
docker compose logs backup | tail -20

# Manually test Google Drive access
docker compose exec backup rclone lsd gdrive:Backup

# You should see your backup folders:
#         -1 2024-01-01 00:00:00        -1 db_backup
#         -1 2024-01-01 00:00:00        -1 uploads
```

## Security Best Practices

1. **Keep the token secure**: Never commit `.env` to git (it's in `.gitignore`)
2. **Rotate periodically**: Generate a new token every few months
3. **Limit folder access**: Use `root_folder_id` to restrict access to specific folder
4. **Monitor usage**: Check Google Drive activity regularly

## Migration from Service Account

If you're migrating from Service Account to OAuth2:

1. **Backup your current .env**:
   ```bash
   cp .env .env.backup-service-account
   ```

2. **Follow the OAuth2 setup above**

3. **Test thoroughly** before removing Service Account credentials

4. **Old backups remain accessible**: Existing files in Google Drive work with both authentication methods

## Next Steps

After successful setup:

1. Your backups will now sync without file creation limits
2. Hourly backups continue automatically in production (RAM mode)
3. Monitor with: `docker compose logs -f backup`
4. Check Google Drive folder to see backups appearing

## Support

If you encounter issues:
- Check logs: `docker compose logs backup`
- Verify token format in .env
- Ensure Google account permissions are correct
- Re-generate token if needed

## Reference

- **rclone OAuth2 docs**: https://rclone.org/drive/#making-your-own-client-id
- **Google OAuth2**: https://developers.google.com/identity/protocols/oauth2
