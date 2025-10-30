import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'utils/keyboard_handler.dart';

class BackendConfigScreen extends StatefulWidget {
  const BackendConfigScreen({super.key});

  @override
  State<BackendConfigScreen> createState() => _BackendConfigScreenState();
}

class _BackendConfigScreenState extends State<BackendConfigScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isTesting = false;
  bool _isConnected = false;
  String _connectionStatus = '';
  Map<String, dynamic> _networkInfo = {};
  List<String> _savedUrls = [];

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
    _loadNetworkInfo();
    _loadSavedUrls();
  }

  void _loadCurrentConfig() {
    _urlController.text = ApiConfig.baseUrl;
  }

  Future<void> _loadNetworkInfo() async {
    final info = await ApiConfig.getNetworkInfo();
    setState(() {
      _networkInfo = info;
    });
  }

  Future<void> _loadSavedUrls() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrls = prefs.getStringList('saved_backend_urls') ?? [];
    setState(() {
      _savedUrls = savedUrls;
    });
  }

  Future<void> _saveUrlToList() async {
    final url = _urlController.text.trim();
    if (url.isEmpty || _savedUrls.contains(url)) return;

    final prefs = await SharedPreferences.getInstance();
    final updatedUrls = [..._savedUrls, url];
    await prefs.setStringList('saved_backend_urls', updatedUrls);
    
    setState(() {
      _savedUrls = updatedUrls;
    });
  }

  Future<void> _removeUrlFromList(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final updatedUrls = _savedUrls.where((u) => u != url).toList();
    await prefs.setStringList('saved_backend_urls', updatedUrls);
    
    setState(() {
      _savedUrls = updatedUrls;
    });
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = 'Testing connection...';
    });

    try {
      final url = _urlController.text.trim();
      if (url.isEmpty) {
        setState(() {
          _connectionStatus = 'Please enter a URL';
          _isConnected = false;
        });
        return;
      }

      // Test the connection
      final response = await http.get(
        Uri.parse('$url/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          _isConnected = true;
          _connectionStatus = '✅ Connected successfully!';
        });
      } else {
        setState(() {
          _isConnected = false;
          _connectionStatus = '❌ Connection failed (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _connectionStatus = '❌ Connection failed: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isTesting = false;
      });
    }
  }

  void _saveConfig() async {
    if (_isConnected) {
      final url = _urlController.text.trim();
      ApiConfig.setBackendUrl(url);
      await _saveUrlToList(); // Save to favorites
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backend URL saved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please test connection first'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _autoDetect() async {
    setState(() {
      _isTesting = true;
      _connectionStatus = 'Auto-detecting backend...';
    });

    ApiConfig.resetDetection();
    await ApiConfig.detectBackend();
    
    setState(() {
      _urlController.text = ApiConfig.baseUrl;
      _isConnected = true;
      _connectionStatus = '✅ Auto-detected: ${ApiConfig.baseUrl}';
      _isTesting = false;
    });
  }

  String _getUrlType(String url) {
    if (url.contains('ngrok.io')) return 'ngrok Tunnel';
    if (url.contains('onrender.com')) return 'Production (Render)';
    if (url.contains('192.168.')) return 'Local Network';
    if (url.contains('10.0.2.2')) return 'Android Emulator';
    if (url.contains('localhost') || url.contains('127.0.0.1')) return 'Local Development';
    return 'Custom URL';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Configuration'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: KeyboardAwareWidget(
        padding: const EdgeInsets.all(16.0),
        bottomSpacing: 150, // Extra space for keyboard
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Network Info Card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Network Information',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Local IP: ${_networkInfo['local_ip'] ?? 'Unknown'}'),
                    Text('Interface: ${_networkInfo['interface'] ?? 'Unknown'}'),
                    Text('Current Backend: ${_networkInfo['backend_url'] ?? 'Not detected'}'),
                    Text('Mode: ${_networkInfo['is_production'] == true ? 'Production' : 'Development'}'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Backend URL Configuration
            Text(
              'Backend URL',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            KeyboardAwareTextField(
              controller: _urlController,
              hintText: 'Enter your backend URL',
              helperText: 'Enter your backend URL (local IP or production)',
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: _testConnection,
              prefixIcon: const Icon(Icons.link),
            ),
            
            const SizedBox(height: 16),
            
            // Connection Status
            if (_connectionStatus.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isConnected ? Icons.check_circle : Icons.error,
                      color: _isConnected ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _connectionStatus,
                        style: TextStyle(
                          color: _isConnected ? Colors.green.shade800 : Colors.red.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            
            const SizedBox(height: 16),
            
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isTesting ? null : _autoDetect,
                    icon: _isTesting 
                        ? const SizedBox(
                            width: 16, 
                            height: 16, 
                            child: CircularProgressIndicator(strokeWidth: 2)
                          )
                        : const Icon(Icons.radar),
                    label: const Text('Auto Detect'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting 
                        ? const SizedBox(
                            width: 16, 
                            height: 16, 
                            child: CircularProgressIndicator(strokeWidth: 2)
                          )
                        : const Icon(Icons.wifi_find),
                    label: const Text('Test'),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Save Button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isConnected ? _saveConfig : null,
                icon: const Icon(Icons.save),
                label: const Text('Save Configuration'),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Saved URLs
            if (_savedUrls.isNotEmpty) ...[
              Text(
                'Saved URLs',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ...(_savedUrls.map((url) => Card(
                child: ListTile(
                  title: Text(url),
                  subtitle: Text(_getUrlType(url)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () {
                          _urlController.text = url;
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _removeUrlFromList(url),
                      ),
                    ],
                  ),
                  onTap: () {
                    _urlController.text = url;
                    _testConnection();
                  },
                ),
              ))),
              const SizedBox(height: 16),
            ],
            
            // Quick URLs
            Text(
              'Quick URLs',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  label: const Text('Local 101'),
                  onPressed: () {
                    _urlController.text = 'http://192.168.0.101:8000';
                  },
                ),
                ActionChip(
                  label: const Text('Emulator'),
                  onPressed: () {
                    _urlController.text = 'http://10.0.2.2:8000';
                  },
                ),
                ActionChip(
                  label: const Text('Localhost'),
                  onPressed: () {
                    _urlController.text = 'http://localhost:8000';
                  },
                ),
              ],
            ),
            
          ],
        ),
      ),
    );
  }
}
