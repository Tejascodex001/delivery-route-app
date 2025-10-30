#!/bin/bash

# ZipRoute ngrok Setup Script
# This script helps you set up ngrok with a constant URL

echo "🚀 ZipRoute ngrok Setup Script"
echo "================================"

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null; then
    echo "❌ ngrok is not installed!"
    echo "Please install ngrok from: https://ngrok.com/download"
    echo "Or run: brew install ngrok (on macOS)"
    exit 1
fi

echo "✅ ngrok is installed"

# Check if backend is running
echo "🔍 Checking if backend is running on port 8000..."
if curl -s http://localhost:8000/health > /dev/null; then
    echo "✅ Backend is running on port 8000"
else
    echo "❌ Backend is not running on port 8000"
    echo "Please start your backend first:"
    echo "  cd backend && python main.py --host 0.0.0.0 --port 8000"
    exit 1
fi

# Get ngrok URL
echo "🔍 Getting ngrok URL..."

# Try to get existing ngrok URL
NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url' 2>/dev/null)

if [ "$NGROK_URL" != "null" ] && [ "$NGROK_URL" != "" ]; then
    echo "✅ Found existing ngrok tunnel: $NGROK_URL"
else
    echo "🔄 Starting new ngrok tunnel..."
    
    # Start ngrok in background
    ngrok http 8000 --log=stdout > ngrok.log 2>&1 &
    NGROK_PID=$!
    
    # Wait for ngrok to start
    sleep 5
    
    # Get the URL
    NGROK_URL=$(curl -s http://localhost:4040/api/tunnels | jq -r '.tunnels[0].public_url' 2>/dev/null)
    
    if [ "$NGROK_URL" != "null" ] && [ "$NGROK_URL" != "" ]; then
        echo "✅ ngrok tunnel started: $NGROK_URL"
    else
        echo "❌ Failed to start ngrok tunnel"
        kill $NGROK_PID 2>/dev/null
        exit 1
    fi
fi

# Test the ngrok URL
echo "🧪 Testing ngrok URL..."
if curl -s "$NGROK_URL/health" > /dev/null; then
    echo "✅ ngrok URL is working: $NGROK_URL"
else
    echo "❌ ngrok URL is not responding"
    exit 1
fi

# Update frontend configuration
echo "🔧 Updating frontend configuration..."

# Create a temporary config file
cat > temp_config.dart << EOF
// ngrok URLs (add your ngrok URL here)
static const List<String> ngrokUrls = [
  '$NGROK_URL',  // Your ngrok URL
  // Add more ngrok URLs as needed
];
EOF

echo "📝 Add this to your frontend/lib/config.dart:"
echo "=============================================="
cat temp_config.dart
echo "=============================================="

# Clean up
rm temp_config.dart

echo ""
echo "🎉 ngrok setup complete!"
echo "================================"
echo "ngrok URL: $NGROK_URL"
echo "Backend URL: http://localhost:8000"
echo "ngrok Dashboard: http://localhost:4040"
echo ""
echo "Next steps:"
echo "1. Update your frontend/lib/config.dart with the ngrok URL above"
echo "2. Rebuild your Flutter app"
echo "3. Test the connection"
echo ""
echo "To stop ngrok: kill $NGROK_PID"
echo "To keep ngrok running: nohup ngrok http 8000 > ngrok.log 2>&1 &"
