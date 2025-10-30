import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/db.dart';
import '../api_client.dart';
import 'package:email_validator/email_validator.dart';
import '../services/location_service.dart';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/error_handler.dart';

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
  final _api = const ApiClient();

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
      // Show user-friendly error message
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, msg.isEmpty ? 'Login failed' : msg);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _guestLogin() async {
    setState(() {
      _loading = true;
    });

    try {
      // Store guest session in SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isGuest', true);
      await prefs.setString('userEmail', 'guest@ziproute.com');
      await prefs.setString('userName', 'Guest User');
      
      // Check location permission for guest
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

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MapScreen()),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Signed in as Guest'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, 'Guest login failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
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
            Card(
              elevation: 0,
              color: Theme.of(context).colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(Icons.delivery_dining,
                              color: Theme.of(context).colorScheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Sign In',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text('Welcome back! Sign in to continue',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7))),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _loading ? null : _signIn,
                      icon: _loading
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login),
                      label: const Text('Sign In'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _guestLogin,
                      icon: const Icon(Icons.person_outline),
                      label: const Text('Continue as Guest'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("Don't have an account? "),
                          TextButton(
                            onPressed: () => Navigator.pushReplacementNamed(context, '/signup'),
                            child: const Text('Sign Up'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


