# 🚀 Google Geocoding API Setup Guide

## Why Google Geocoding API?
- ✅ **99% accuracy** for any address worldwide
- ✅ **Handles complex addresses** like "PES College, Hanumanthnagar, Bangalore"
- ✅ **Real-time results**
- ✅ **Very affordable**: $5 per 1000 requests

## Quick Setup (5 minutes):

### Step 1: Get Google API Key
1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project or select existing one
3. Go to **APIs & Services** → **Credentials**
4. Click **Create Credentials** → **API Key**
5. Copy your API key

### Step 2: Enable Geocoding API
1. Go to **APIs & Services** → **Library**
2. Search for "Geocoding API"
3. Click **Enable**

### Step 3: Add API Key to Your App
1. Open `backend/main.py`
2. Find this line:
   ```python
   GOOGLE_GEOCODING_API_KEY: str = ""  # Paste your Google API key here
   ```
3. Paste your API key:
   ```python
   GOOGLE_GEOCODING_API_KEY: str = "YOUR_API_KEY_HERE"
   ```

### Step 4: Restart Backend
```bash
# Kill current backend
pkill -f "python main.py"

# Restart with new API key
conda activate route_optimize && cd backend && python main.py
```

## 🎯 Test It:
Try these addresses that will now work perfectly:
- `"PES College, Hanumanthnagar, Bangalore"`
- `"Global Academy of Technology, Rajarajeshwari Nagar, Bangalore"`
- `"PES College, Hosakerehalli, Bangalore"`

## 💰 Cost:
- **Free tier**: $200 credit (covers ~40,000 geocoding requests)
- **After free tier**: $5 per 1000 requests
- **For a delivery app**: Very affordable even for heavy usage

## 🔒 Security:
- Set up API key restrictions in Google Cloud Console
- Restrict to your server's IP address
- Monitor usage in Google Cloud Console

## Alternative: Mapbox (Free Option)
If you prefer a free option:
1. Sign up at [Mapbox](https://www.mapbox.com/)
2. Get your access token
3. Replace Google API with Mapbox API (I can help you with this)

---
**Your delivery route optimization app will now work with ANY address worldwide! 🌍**
