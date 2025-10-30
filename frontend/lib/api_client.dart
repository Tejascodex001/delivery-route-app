import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'utils/error_handler.dart';

class ApiClient {
  static String get baseUrl => ApiConfig.baseUrl;
  const ApiClient();

  Future<Map<String, dynamic>> planFullRoute({
    required List<String> addresses,
    String? startTimeIso,
    String? vehicleStartAddress,
  }) async {
    final uri = Uri.parse('$baseUrl/plan-full-route');
    final body = <String, dynamic>{
      'addresses': addresses,
      if (startTimeIso != null) 'start_time': startTimeIso,
      if (vehicleStartAddress != null)
        'vehicle_start_address': vehicleStartAddress,
    };
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      final errorMessage = ErrorHandler.handleApiResponse(resp.body, resp.statusCode);
      throw Exception(errorMessage);
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> extractTextFromImage(File file) async {
    final uri = Uri.parse('$baseUrl/ocr/extract-text');
    final request = http.MultipartRequest('POST', uri);
    request.files.add(await http.MultipartFile.fromPath('image', file.path));
    final streamed = await request.send();
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode != 200) {
      final errorMessage = ErrorHandler.handleApiResponse(resp.body, resp.statusCode);
      throw Exception('OCR error: $errorMessage');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> searchSuggestions(String query) async {
    final uri = Uri.parse('$baseUrl/search-suggestions').replace(queryParameters: {
      'q': query,
    });
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      final errorMessage = ErrorHandler.handleApiResponse(resp.body, resp.statusCode);
      throw Exception('Search error: $errorMessage');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['suggestions'] ?? []);
  }

  Future<List<Map<String, dynamic>>> getNearbyPlaces(double lat, double lon, {int radius = 5000}) async {
    final uri = Uri.parse('$baseUrl/nearby-places').replace(queryParameters: {
      'lat': lat.toString(),
      'lon': lon.toString(),
      'radius': radius.toString(),
    });
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      final errorMessage = ErrorHandler.handleApiResponse(resp.body, resp.statusCode);
      throw Exception('Nearby places error: $errorMessage');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['places'] ?? []);
  }

  // -------- Auth --------
  Future<Map<String, dynamic>> register({required String email, required String password, String? name}) async {
    final uri = Uri.parse('$baseUrl/auth/register');
    final resp = await http.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password, 'name': name}));
    if (resp.statusCode == 409) {
      throw Exception('User already exists');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final errorMessage = ErrorHandler.handleApiResponse(resp.body, resp.statusCode);
      throw Exception(errorMessage);
    }
    final body = resp.body.isEmpty ? '{}' : resp.body;
    final data = jsonDecode(body) as Map<String, dynamic>;
    return data;
  }

  Future<Map<String, dynamic>> verifyEmail({required String email, required String otp}) async {
    final uri = Uri.parse('$baseUrl/auth/verify-email');
    final resp = await http.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final errorMessage = ErrorHandler.handleApiResponse(resp.body, resp.statusCode);
      throw Exception(errorMessage);
    }
    final body = resp.body.isEmpty ? '{}' : resp.body;
    final data = jsonDecode(body) as Map<String, dynamic>;
    return data;
  }

  Future<Map<String, dynamic>> login({required String email, required String password}) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    final resp = await http.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}));
    if (resp.statusCode == 403) {
      throw Exception('Email not verified');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      final errorMessage = ErrorHandler.handleApiResponse(resp.body, resp.statusCode);
      throw Exception(errorMessage);
    }
    final body = resp.body.isEmpty ? '{}' : resp.body;
    final data = jsonDecode(body) as Map<String, dynamic>;
    return data;
  }
}


