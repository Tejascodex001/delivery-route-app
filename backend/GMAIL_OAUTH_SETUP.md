# Gmail OAuth2 API Setup for Dynamic Email Sending

This setup allows the app to send verification emails from any Gmail account using OAuth2 authentication.

## Step 1: Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Enable the Gmail API:
   - Go to "APIs & Services" > "Library"
   - Search for "Gmail API"
   - Click "Enable"

## Step 2: Create OAuth2 Credentials

1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth client ID"
3. Choose "Desktop application"
4. Name it "Delivery Route Optimizer"
5. Download the JSON file and rename it to `credentials.json`
6. Place `credentials.json` in the `backend/` folder

## Step 3: Install Dependencies

```bash
cd backend
conda activate route_optimize
pip install google-auth google-auth-oauthlib google-auth-httplib2 google-api-python-client
```

## Step 4: First-Time Authentication

1. Start the backend:
   ```bash
   python main.py
   ```

2. On first run, it will open a browser window for OAuth authentication
3. Sign in with the Gmail account you want to send emails from
4. Grant permissions to the app
5. The system will save the token for future use

## Step 5: Test Email Sending

1. Register a new user in your app
2. Check the Gmail inbox for the verification email
3. The email will have a beautiful HTML design with the OTP

## Features

- **Dynamic**: Works with any Gmail account
- **Secure**: Uses OAuth2 instead of app passwords
- **Beautiful**: Professional HTML email template
- **Automatic**: Token refresh handled automatically
- **Fallback**: Console logging if Gmail API fails

## Files Created

- `credentials.json` - OAuth2 client credentials (keep secure)
- `token.json` - User authentication token (auto-generated)

## Troubleshooting

- If browser doesn't open: Check firewall/network settings
- If permission denied: Ensure Gmail API is enabled in Google Cloud
- If emails don't arrive: Check spam folder
- If token expires: Delete `token.json` and re-authenticate

## Security Notes

- Never commit `credentials.json` or `token.json` to version control
- Add them to `.gitignore`
- The OAuth2 flow only requests minimal permissions (send emails)
