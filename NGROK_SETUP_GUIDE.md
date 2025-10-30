# ngrok Setup Guide for ZipRoute Backend

## 🚀 **Getting a Constant ngrok URL**

### **Option 1: Free ngrok with Custom Subdomain (Limited)**
```bash
# Install ngrok
# Download from: https://ngrok.com/download

# Run with custom subdomain (free tier limitations)
ngrok http 8000 --subdomain=ziproute-backend
# This gives you: https://ziproute-backend.ngrok.io
```

### **Option 2: ngrok with Reserved Domain (Paid - $8/month)**
```bash
# This gives you a permanent URL
ngrok http 8000 --domain=ziproute-backend.ngrok.io
# This gives you: https://ziproute-backend.ngrok.io (permanent)
```

### **Option 3: Free ngrok (Temporary URL)**
```bash
# This gives you a random URL that changes each time
ngrok http 8000
# Example output: https://abc123.ngrok.io
```

## 🔧 **Update Your Frontend Configuration**

### **Step 1: Update config.dart**
Replace the ngrok URL in your `frontend/lib/config.dart`:

```dart
// ngrok URLs (add your ngrok URL here)
static const List<String> ngrokUrls = [
  'https://ziproute-backend.ngrok.io',  // Your custom ngrok domain
  'https://abc123.ngrok.io',            // Replace with your actual ngrok URL
  // Add more ngrok URLs as needed
];
```

### **Step 2: Update Network Security Config**
The `network_security_config.xml` has been updated to allow ngrok domains.

## 🔧 **Fix Frontend Disconnection Issues**

### **Problem 1: Connection Timeouts**
Add retry logic to your API client:

```dart
// In your api_client.dart, add retry logic
static Future<http.Response> _makeRequestWithRetry(
  Future<http.Response> Function() request, {
  int maxRetries = 3,
  Duration delay = const Duration(seconds: 1),
}) async {
  for (int i = 0; i < maxRetries; i++) {
    try {
      final response = await request().timeout(const Duration(seconds: 30));
      return response;
    } catch (e) {
      if (i == maxRetries - 1) rethrow;
      await Future.delayed(delay * (i + 1));
    }
  }
  throw Exception('Max retries exceeded');
}
```

### **Problem 2: CORS Issues**
Update your backend to handle CORS properly:

```python
# In your backend/main.py, add CORS middleware
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your frontend domain
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### **Problem 3: Keep ngrok Session Alive**
Create a script to keep ngrok running:

```bash
#!/bin/bash
# keep_ngrok_alive.sh
while true; do
    ngrok http 8000 --log=stdout
    echo "ngrok disconnected, restarting in 5 seconds..."
    sleep 5
done
```

## 🔧 **Test All Endpoints**

### **Step 1: Start Your Backend**
```bash
cd backend
python main.py --host 0.0.0.0 --port 8000
```

### **Step 2: Start ngrok**
```bash
# In another terminal
ngrok http 8000 --subdomain=ziproute-backend
```

### **Step 3: Test the Connection**
```bash
# Test health endpoint
curl https://ziproute-backend.ngrok.io/health

# Test all endpoints
curl https://ziproute-backend.ngrok.io/docs
curl https://ziproute-backend.ngrok.io/openapi.json
```

### **Step 4: Update Frontend**
1. Replace the ngrok URL in `config.dart`
2. Rebuild your Flutter app
3. Test the connection

## 🔧 **Troubleshooting Common Issues**

### **Issue 1: "Connection Refused"**
- **Cause**: ngrok tunnel not running or backend not started
- **Solution**: 
  ```bash
  # Check if backend is running
  curl http://localhost:8000/health
  
  # Check if ngrok is running
  curl https://your-ngrok-url.ngrok.io/health
  ```

### **Issue 2: "CORS Error"**
- **Cause**: Backend not configured for CORS
- **Solution**: Add CORS middleware to your backend

### **Issue 3: "Timeout"**
- **Cause**: Network issues or slow response
- **Solution**: Increase timeout in your API client

### **Issue 4: "SSL Certificate Error"**
- **Cause**: ngrok SSL certificate issues
- **Solution**: Use HTTP instead of HTTPS for testing (not recommended for production)

## 🔧 **Production Deployment Options**

### **Option 1: Keep using ngrok (Development)**
- **Pros**: Easy setup, works immediately
- **Cons**: URL changes, not suitable for production

### **Option 2: Deploy to Cloud (Recommended)**
- **Render**: Free tier available
- **Heroku**: Free tier available
- **Railway**: Free tier available
- **DigitalOcean**: $5/month

### **Option 3: Use a VPS**
- **DigitalOcean Droplet**: $5/month
- **AWS EC2**: Pay as you go
- **Google Cloud**: Free tier available

## 🔧 **Testing Your Setup**

### **Test Script**
```bash
#!/bin/bash
# test_ngrok_setup.sh

NGROK_URL="https://your-ngrok-url.ngrok.io"

echo "Testing ngrok setup..."

# Test health endpoint
echo "1. Testing health endpoint..."
curl -s "$NGROK_URL/health" | jq .

# Test API docs
echo "2. Testing API docs..."
curl -s "$NGROK_URL/docs" | head -20

# Test OpenAPI schema
echo "3. Testing OpenAPI schema..."
curl -s "$NGROK_URL/openapi.json" | jq .info

echo "✅ ngrok setup test complete!"
```

## 🔧 **Best Practices**

### **1. Keep ngrok Running**
- Use a process manager like PM2
- Set up auto-restart on failure
- Monitor ngrok logs

### **2. Security**
- Don't expose sensitive endpoints
- Use authentication
- Rate limit your API

### **3. Monitoring**
- Monitor ngrok status
- Set up alerts for disconnections
- Log all requests

## 🔧 **Next Steps**

1. **Set up ngrok** with your preferred method
2. **Update your frontend** configuration
3. **Test all endpoints** to ensure they work
4. **Deploy to production** when ready
5. **Monitor and maintain** your setup

## 🔧 **Support**

If you encounter issues:
1. Check ngrok logs: `ngrok http 8000 --log=stdout`
2. Check backend logs: Look at your Python console
3. Test with curl: `curl https://your-ngrok-url.ngrok.io/health`
4. Check network connectivity: `ping your-ngrok-url.ngrok.io`

Remember: ngrok is great for development and testing, but for production, consider deploying to a proper cloud service!
