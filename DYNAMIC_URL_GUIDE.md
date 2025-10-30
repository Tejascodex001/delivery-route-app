# Dynamic URL Input Guide for ZipRoute

## 🎯 **How to Use Dynamic URL Input in Your App**

### **✅ What's New:**
- **No More Hardcoding**: Enter any URL directly in the app
- **Save Favorites**: Save frequently used URLs for quick access
- **Auto-Detection**: Automatically find your backend
- **URL Types**: Automatically identify ngrok, local, production URLs
- **One-Tap Testing**: Test connections with a single tap

---

## 🚀 **How to Access the URL Input Screen**

### **Method 1: From Settings Menu**
1. Open your ZipRoute app
2. Tap the menu (☰) in the top-left corner
3. Tap "Backend Configuration"
4. You'll see the URL input screen

### **Method 2: From Main Screen**
1. Look for the network status indicator in the app bar
2. Tap on it to open backend configuration

---

## 📝 **How to Enter Your ngrok URL**

### **Step 1: Get Your ngrok URL**
```bash
# Start your backend
cd backend
python main.py --host 0.0.0.0 --port 8000

# In another terminal, start ngrok
ngrok http 8000

# Copy the https URL (e.g., https://abc123.ngrok.io)
```

### **Step 2: Enter URL in App**
1. Open "Backend Configuration" in your app
2. In the "Backend URL" field, paste your ngrok URL
3. Tap "Test" to verify the connection
4. If successful, tap "Save Configuration"

### **Step 3: Save for Future Use**
- The URL will be automatically saved to your favorites
- Next time, just tap on the saved URL to use it instantly

---

## 🔧 **Features Explained**

### **1. URL Input Field**
- **Smart Keyboard**: URL keyboard for easy typing
- **Auto-Complete**: Suggests common URL patterns
- **Enter to Test**: Press Enter to test connection immediately

### **2. Quick URL Buttons**
- **Production**: Your Render.com backend
- **ngrok.io**: Starts with https:// for easy ngrok entry
- **Local 101**: Your local IP (192.168.0.101:8000)
- **Emulator**: Android emulator (10.0.2.2:8000)
- **Localhost**: Local development (localhost:8000)

### **3. Saved URLs Section**
- **Auto-Save**: URLs are saved when you successfully connect
- **Quick Access**: Tap any saved URL to use it
- **Edit/Delete**: Manage your saved URLs
- **URL Types**: See if it's ngrok, local, production, etc.

### **4. Connection Testing**
- **Real-Time Status**: See connection status immediately
- **Error Messages**: Clear error messages if connection fails
- **Auto-Detection**: Automatically find your backend

---

## 🎯 **Common Use Cases**

### **Case 1: Using ngrok for Development**
1. Start ngrok: `ngrok http 8000`
2. Copy the https URL
3. Paste in app and test
4. Save for future use

### **Case 2: Switching Between Networks**
1. Save your home network URL: `http://192.168.1.100:8000`
2. Save your office network URL: `http://192.168.0.50:8000`
3. Save your ngrok URL: `https://abc123.ngrok.io`
4. Switch between them as needed

### **Case 3: Testing Different Backends**
1. Save production URL: `https://delivery-w97o.onrender.com`
2. Save local development URL: `http://localhost:8000`
3. Save staging URL: `https://staging-backend.ngrok.io`
4. Switch between them for testing

---

## 🔧 **Troubleshooting**

### **Problem: "Connection Failed"**
**Solutions:**
1. Check if your backend is running
2. Verify the URL is correct
3. Check if ngrok is running (for ngrok URLs)
4. Try the "Auto Detect" button

### **Problem: "URL Not Saved"**
**Solutions:**
1. Make sure connection test passes first
2. Check if URL is already saved
3. Try saving again after successful test

### **Problem: "Auto Detect Not Working"**
**Solutions:**
1. Make sure you're on the same network
2. Check if backend is accessible
3. Try manual URL entry instead

---

## 📱 **App Interface Guide**

### **Main Screen Elements:**
- **URL Input Field**: Enter your backend URL here
- **Test Button**: Test the connection
- **Auto Detect Button**: Automatically find backend
- **Save Button**: Save the configuration
- **Saved URLs**: List of your saved URLs
- **Quick URLs**: Common URL shortcuts
- **Help Card**: Step-by-step ngrok setup guide

### **Connection Status Indicators:**
- **✅ Green**: Connection successful
- **❌ Red**: Connection failed
- **⏳ Loading**: Testing connection
- **ℹ️ Info**: Connection details

---

## 🎉 **Benefits**

### **✅ No More Hardcoding**
- Change URLs without rebuilding the app
- Switch between different backends easily
- Test with different environments

### **✅ User-Friendly**
- Simple interface for non-technical users
- Clear error messages and help text
- One-tap URL switching

### **✅ Persistent Storage**
- URLs saved between app sessions
- Quick access to frequently used URLs
- Automatic URL type detection

### **✅ Flexible Development**
- Easy switching between local and remote backends
- Support for ngrok, local networks, and production
- Auto-detection for convenience

---

## 🚀 **Next Steps**

1. **Open your app** and go to Backend Configuration
2. **Enter your ngrok URL** and test the connection
3. **Save the configuration** for future use
4. **Enjoy seamless backend switching** without rebuilding!

Your app now supports dynamic URL input - no more hardcoding URLs! 🎉
