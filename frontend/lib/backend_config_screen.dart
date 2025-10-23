import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'config.dart';

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

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
    _loadNetworkInfo();
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

  void _saveConfig() {
    if (_isConnected) {
      ApiConfig.setBackendUrl(_urlController.text.trim());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Backend URL saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please test connection first'),
          backgroundColor: Colors.orange,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Backend Configuration'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
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
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.100:8000',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
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
                  label: const Text('Production'),
                  onPressed: () {
                    _urlController.text = ApiConfig.prodBaseUrl;
                  },
                ),
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
