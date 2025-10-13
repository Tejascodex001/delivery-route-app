import 'dart:convert';
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
}


