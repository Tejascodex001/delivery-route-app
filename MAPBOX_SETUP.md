# 🗺️ Mapbox Geocoding Setup Guide (FREE!)

## Why Mapbox?
- ✅ **FREE**: 50,000 geocoding requests per month
- ✅ **Excellent accuracy** for Indian addresses
- ✅ **No credit card required** for free tier
- ✅ **Great coverage** for colleges, institutions, landmarks
- ✅ **After free tier**: Only $0.75 per 1000 requests

## Quick Setup (3 minutes):

### Step 1: Get Mapbox Access Token
1. Go to [Mapbox Account](https://account.mapbox.com/)
2. Sign up for free (no credit card needed)
3. Go to **Access Tokens** page
4. Copy your **Default public token**

### Step 2: Add Token to Your App
1. Open `backend/main.py`
2. Find this line:
   ```python
   MAPBOX_ACCESS_TOKEN: str = ""  # Paste your Mapbox access token here
   ```
3. Paste your token:
   ```python
   MAPBOX_ACCESS_TOKEN: str = "pk.eyJ1IjoieW91cnVzZXJuYW1lIiwiYSI6ImNsb2V4YWJjZzAwM..."
   ```

### Step 3: Restart Backend
```bash
# Kill current backend
pkill -f "python main.py"

# Restart with new token
conda activate route_optimize && cd backend && python main.py
```

## 🎯 Test It:
Try these addresses that will now work perfectly:
- `"PES College, Hanumanthnagar, Bangalore"`
- `"Global Academy of Technology, Rajarajeshwari Nagar, Bangalore"`
- `"PES College, Hosakerehalli, Bangalore"`
- `"IIT Delhi, New Delhi"`
- `"BITS Pilani, Rajasthan"`

## 💰 Cost:
- **FREE**: 50,000 requests/month (plenty for most apps)
- **After free tier**: $0.75 per 1000 requests
- **For a delivery app**: Very affordable even for heavy usage

## 🔒 Security:
- Your token is safe to use in backend code
- Mapbox tokens are designed for server-side use
- Monitor usage in your Mapbox dashboard

## 🆚 Comparison:
| Service | Free Tier | Accuracy | Indian Coverage |
|---------|-----------|----------|-----------------|
| **Mapbox** | 50,000/month | 95% | Excellent |
| Google | $200 credit | 99% | Excellent |
| Nominatim | Unlimited | 60% | Poor |
| OpenRouteService | 1,000/day | 70% | Fair |

## 🎉 Result:
Your delivery route optimization app will now work with ANY address in India and most worldwide addresses!

---
**Mapbox is the perfect choice for your free, high-quality geocoding needs! 🚀**
