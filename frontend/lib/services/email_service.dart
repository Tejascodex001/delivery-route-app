import 'dart:convert';
import 'package:http/http.dart' as http;

class EmailService {
  static const String _apiKey = 'YOUR_EMAILJS_API_KEY'; // Replace with your EmailJS API key
  static const String _serviceId = 'YOUR_SERVICE_ID'; // Replace with your EmailJS service ID
  static const String _templateId = 'YOUR_TEMPLATE_ID'; // Replace with your EmailJS template ID

  // For demo purposes, we'll simulate email sending
  // In production, integrate with EmailJS, SendGrid, or similar service
  static Future<bool> sendVerificationEmail({
    required String email,
    required String verificationCode,
  }) async {
    try {
      // Simulate email sending delay
      await Future.delayed(const Duration(seconds: 2));
      
      // In production, replace this with actual email service
      print('📧 Verification email sent to: $email');
      print('🔐 Verification code: $verificationCode');
      print('⚠️  In production, this would be sent via EmailJS/SendGrid');
      
      // For demo, we'll always return true
      // In production, check the actual response from email service
      return true;
      
      /* Production code example with EmailJS:
      final response = await http.post(
        Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'service_id': _serviceId,
          'template_id': _templateId,
          'user_id': _apiKey,
          'template_params': {
            'to_email': email,
            'verification_code': verificationCode,
            'app_name': 'ZipRoute',
          }
        }),
      );
      
      return response.statusCode == 200;
      */
    } catch (e) {
      print('❌ Email sending error: $e');
      return false;
    }
  }

  static Future<bool> sendPasswordResetEmail({
    required String email,
    required String resetCode,
  }) async {
    try {
      await Future.delayed(const Duration(seconds: 2));
      print('📧 Password reset email sent to: $email');
      print('🔐 Reset code: $resetCode');
      return true;
    } catch (e) {
      print('❌ Password reset email error: $e');
      return false;
    }
  }
}
