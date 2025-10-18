import 'dart:convert';
import 'package:http/http.dart' as http;

class TrainingData {
  final String routeId;
  final List<String> addresses;
  final List<List<double>> coordinates;
  final double predictedEtaMinutes;
  final double? actualEtaMinutes;
  final String startTime;
  final DateTime? endTime;
  final List<Map<String, dynamic>> sensorData;
  final String userId;
  final Map<String, dynamic> routeMetadata;

  TrainingData({
    required this.routeId,
    required this.addresses,
    required this.coordinates,
    required this.predictedEtaMinutes,
    this.actualEtaMinutes,
    required this.startTime,
    this.endTime,
    required this.sensorData,
    required this.userId,
    required this.routeMetadata,
  });

  Map<String, dynamic> toJson() {
    return {
      'route_id': routeId,
      'addresses': addresses,
      'coordinates': coordinates,
      'predicted_eta_minutes': predictedEtaMinutes,
      'actual_eta_minutes': actualEtaMinutes,
      'start_time': startTime,
      'end_time': endTime?.toIso8601String(),
      'sensor_data': sensorData,
      'user_id': userId,
      'route_metadata': routeMetadata,
    };
  }
}

class TrainingDataService {
  static final TrainingDataService _instance = TrainingDataService._internal();
  factory TrainingDataService() => _instance;
  TrainingDataService._internal();

  final String baseUrl = 'http://192.168.0.101:8000';
  final List<TrainingData> _pendingData = [];

  Future<void> submitTrainingData(TrainingData data) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/submit-training-data'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data.toJson()),
      );

      if (response.statusCode == 200) {
        print('✅ Training data submitted successfully');
      } else {
        print('❌ Failed to submit training data: ${response.statusCode}');
        // Store for retry
        _pendingData.add(data);
      }
    } catch (e) {
      print('❌ Error submitting training data: $e');
      // Store for retry
      _pendingData.add(data);
    }
  }

  Future<void> retryPendingData() async {
    final dataToRetry = List<TrainingData>.from(_pendingData);
    _pendingData.clear();

    for (final data in dataToRetry) {
      await submitTrainingData(data);
    }
  }

  Future<void> updateActualEta(String routeId, double actualEtaMinutes) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/update-actual-eta'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'route_id': routeId,
          'actual_eta_minutes': actualEtaMinutes,
        }),
      );

      if (response.statusCode == 200) {
        print('✅ Actual ETA updated successfully');
      } else {
        print('❌ Failed to update actual ETA: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error updating actual ETA: $e');
    }
  }

  // Generate unique route ID
  String generateRouteId() {
    return 'route_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecond % 1000).toString().padLeft(3, '0')}';
  }
}
