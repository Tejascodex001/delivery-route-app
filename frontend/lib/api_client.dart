import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl; // e.g., http://127.0.0.1:8000
  const ApiClient({required this.baseUrl});

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
      throw Exception('Backend error: ${resp.statusCode} ${resp.body}');
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
      throw Exception('OCR error: ${resp.statusCode} ${resp.body}');
    }
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> searchSuggestions(String query) async {
    final uri = Uri.parse('$baseUrl/search-suggestions').replace(queryParameters: {
      'q': query,
    });
    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('Search error: ${resp.statusCode} ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    return List<Map<String, dynamic>>.from(data['suggestions'] ?? []);
  }
}


