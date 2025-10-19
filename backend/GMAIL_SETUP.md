# Gmail SMTP Setup for Email Verification

## Step 1: Enable 2-Factor Authentication
1. Go to [Google Account Security](https://myaccount.google.com/security)
2. Enable 2-Factor Authentication if not already enabled

## Step 2: Generate App Password
1. Go to [Google Account Security](https://myaccount.google.com/security)
2. Click on "2-Step Verification"
3. Scroll down to "App passwords"
4. Click "App passwords"
5. Select "Mail" and "Other (custom name)"
6. Enter "Delivery Route Optimizer" as the name
7. Copy the generated 16-character password (e.g., `abcd efgh ijkl mnop`)

## Step 3: Update Code
Edit `backend/main.py` and update these lines (around line 133-134):

```python
GMAIL_USER = "your-actual-email@gmail.com"  # Replace with your Gmail address
GMAIL_APP_PASSWORD = "your-16-char-app-password"  # Replace with your App Password
```

## Step 4: Restart Backend
```bash
cd backend
conda activate route_optimize
python main.py
```

## Testing
1. Register a new user
2. Check your email inbox for the verification code
3. The email will have a nice HTML format with the OTP prominently displayed

## Troubleshooting
- If emails don't arrive, check spam folder
- If you get authentication errors, verify the app password is correct
- If still failing, the system will fall back to console logging
