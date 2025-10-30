import 'dart:io';
import 'package:http/http.dart' as http;

class ApiConfig {
  // Production backend (Render)
  static const String prodBaseUrl = '';
  
  // ngrok URLs (add your ngrok URL here)
  static const List<String> ngrokUrls = [
    'https://unseasonable-emely-unvoluminous.ngrok-free.dev',  // Your current ngrok URL
    'https://ziproute-backend.ngrok.io',  // Your custom ngrok domain
    'https://abc123.ngrok.io',            // Replace with your actual ngrok URL
    // Add more ngrok URLs as needed
  ];
  
  // Common local development URLs to try
  static const List<String> localUrls = [
    'http://192.168.0.101:8000',  // Your current IP
    'http://192.168.1.101:8000',  // Common alternative
    'http://10.0.2.2:8000',       // Android emulator
    'http://localhost:8000',       // Local development
    'http://127.0.0.1:8000',      // Local development
    // Mobile hotspot common IPs
    'http://192.168.43.1:8000',   // Android hotspot default
    'http://192.168.137.1:8000',  // Windows mobile hotspot
    'http://10.0.0.1:8000',       // Some mobile hotspots
    'http://172.20.10.1:8000',    // iOS hotspot default
  ];
  
  // Network ranges to scan
  static const List<String> networkRanges = [
    '192.168.0',   // Common home network
    '192.168.1',   // Common home network
    '192.168.4',   // Mobile hotspot
    '192.168.43',  // Android hotspot
    '192.168.137', // Windows mobile hotspot
    '172.20.10',   // iOS hotspot
    '10.0.0',      // Corporate network
    '172.16.0',    // Corporate network
  ];
  
  static String? _detectedBackendUrl;
  static bool _isProduction = false;
  
  // Get the current backend URL
  static String get baseUrl {
    if (_detectedBackendUrl != null) {
      return _detectedBackendUrl!;
    }
    
    // Try to detect automatically
    detectBackend();
    
    // Return production URL as fallback
    return prodBaseUrl;
  }
  
  // Check if we're using production backend
  static bool get isProduction => _isProduction;
  
  // Detect backend URL automatically
  static Future<void> detectBackend() async {
    print('🔍 Detecting backend URL...');
    
    // First, try ngrok URLs (for development with public access)
    for (String url in ngrokUrls) {
      if (await _testUrl(url)) {
        _detectedBackendUrl = url;
        _isProduction = true; // ngrok URLs are considered production-like
        print('✅ Using ngrok backend: $url');
        return;
      }
    }
    
    // Try production URL
    if (await _testUrl(prodBaseUrl)) {
      _detectedBackendUrl = prodBaseUrl;
      _isProduction = true;
      print('✅ Using production backend: $prodBaseUrl');
      return;
    }
    
    // Try common local URLs
    for (String url in localUrls) {
      if (await _testUrl(url)) {
        _detectedBackendUrl = url;
        _isProduction = false;
        print('✅ Using local backend: $url');
        return;
      }
    }
    
    // Try network scanning
    String? scannedUrl = await _scanNetwork();
    if (scannedUrl != null) {
      _detectedBackendUrl = scannedUrl;
      _isProduction = false;
      print('✅ Found backend via network scan: $scannedUrl');
      return;
    }
    
    // Fallback to production
    _detectedBackendUrl = prodBaseUrl;
    _isProduction = true;
    print('⚠️ Using production backend as fallback: $prodBaseUrl');
  }
  
  // Test if a URL is reachable
  static Future<bool> _testUrl(String url) async {
    try {
      final response = await http.get(
        Uri.parse('$url/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 3));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  // Scan network for backend
  static Future<String?> _scanNetwork() async {
    print('🔍 Scanning network for backend...');
    
    for (String range in networkRanges) {
      // Try common ports
      List<int> ports = [8000, 3000, 5000, 8080];
      
      for (int port in ports) {
        // Try a few IPs in each range
        for (int i = 1; i <= 20; i++) {
          String ip = '$range.$i';
          String url = 'http://$ip:$port';
          
          if (await _testUrl(url)) {
            return url;
          }
        }
      }
    }
    
    return null;
  }
  
  // Manually set backend URL
  static void setBackendUrl(String url) {
    _detectedBackendUrl = url;
    _isProduction = url.startsWith('https://');
    print('🔧 Manually set backend URL: $url');
  }
  
  // Reset detection (force re-detection)
  static void resetDetection() {
    _detectedBackendUrl = null;
    _isProduction = false;
    print('🔄 Reset backend detection');
  }
  
  // Get current network info
  static Future<Map<String, dynamic>> getNetworkInfo() async {
    try {
      // Get local IP
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return {
              'local_ip': addr.address,
              'interface': interface.name,
              'backend_url': _detectedBackendUrl ?? 'Not detected',
              'is_production': _isProduction,
            };
          }
        }
      }
    } catch (e) {
      print('Error getting network info: $e');
    }
    
    return {
      'local_ip': 'Unknown',
      'interface': 'Unknown',
      'backend_url': _detectedBackendUrl ?? 'Not detected',
      'is_production': _isProduction,
    };
  }
}
