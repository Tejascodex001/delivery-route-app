import 'package:flutter/material.dart';
// Removed local DB/email demo in favor of backend auth
// import '../services/db.dart';
// import '../services/email_service.dart';
import '../api_client.dart';
import 'package:email_validator/email_validator.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});
  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final _api = const ApiClient(baseUrl: 'http://192.168.0.101:8000');

  Future<void> _signUp() async {
    // Clear any prefilled values
    _email.text = _email.text.trim();

    // Email validation
    if (!EmailValidator.validate(_email.text)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address')),
      );
      return;
    }

    // Strong password validation
    final pwd = _password.text;
    // final confirm = _confirmPassword.text; // not needed beyond equality check
    final strong = _isStrongPassword(pwd);
    if (!strong) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be 8+ chars with upper, lower, digit, special')),
      );
      return;
    }

    if (_password.text != _confirmPassword.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match')),
      );
      return;
    }

    // length already enforced via strong password

    setState(() => _loading = true);
    try {
      final res = await _api.register(email: _email.text, password: _password.text);
      if (!mounted) return;
      final msg = (res['message'] ?? '').toString().toLowerCase();
      if (msg.contains('already exists') && msg.contains('verified')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account already verified. Please sign in.')),
        );
        Navigator.pushReplacementNamed(context, '/signin');
      } else {
        Navigator.pushReplacementNamed(
          context,
          '/verify-email',
          arguments: {'email': _email.text},
        );
      }
    } on Exception catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _isStrongPassword(String value) {
    // At least 8 chars, 1 upper, 1 lower, 1 digit, 1 special (non-alphanumeric)
    final regex = RegExp(r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9]).{8,}$");
    return regex.hasMatch(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
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
              'Join Delivery Route Optimizer',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Create your account to start optimizing routes',
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
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPassword,
              obscureText: _obscureConfirmPassword,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _signUp,
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
                  : const Text('Create Account', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Already have an account? '),
                TextButton(
                  onPressed: () => Navigator.pushReplacementNamed(context, '/signin'),
                  child: const Text('Sign In'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}


