import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/db.dart';
import '../api_client.dart';
import 'package:email_validator/email_validator.dart';
import '../services/location_service.dart';
import '../main.dart';

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});
  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  final _api = const ApiClient(baseUrl: 'http://192.168.0.101:8000');

  Future<void> _signIn() async {
    // Clear any prefilled spaces
    _email.text = _email.text.trim();
    if (!EmailValidator.validate(_email.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await _api.login(email: _email.text, password: _password.text);
      
      if (!mounted) return;

      // Save session
      await DatabaseProvider.instance.saveSession(
        email: _email.text,
        userId: (result['user_id'] is int)
            ? result['user_id'] as int
            : int.tryParse('${result['user_id']}') ?? 0,
      );

      // Check location permission
      final locationEnabled = await LocationService.isLocationEnabled();
      var permission = await LocationService.checkPermission();

      if (!mounted) return;

      if (!locationEnabled || permission == LocationPermission.denied) {
        final wantsEnable = await _showLocationDialog();
        if (wantsEnable != true) return; // user cancelled
        permission = await LocationService.requestPermission();
        if (!mounted) return;
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission is required to proceed.')),
          );
          return;
        }
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MapScreen()),
      );
    } on Exception catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      // Always show a generic error; do not auto-route to verification on login
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.isEmpty ? 'Login failed' : msg)),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool?> _showLocationDialog() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Access Required'),
        content: const Text(
          'This app needs location access to optimize your delivery routes. '
          'Please enable location services to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable Location'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome Back'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            const Icon(
              Icons.delivery_dining,
              size: 80,
              color: Colors.indigo,
            ),
            const SizedBox(height: 20),
            const Text(
              'Sign In',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Welcome back! Sign in to continue',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _password,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _signIn,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Sign In', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text("Don't have an account? "),
                TextButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
                  child: const Text('Sign Up'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


