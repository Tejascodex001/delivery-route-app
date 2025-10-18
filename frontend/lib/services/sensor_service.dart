import 'dart:async';
import 'dart:io';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:device_info_plus/device_info_plus.dart';

class SensorData {
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final double? speed;
  final double? heading;
  final double? accelerationX;
  final double? accelerationY;
  final double? accelerationZ;
  final double? gyroscopeX;
  final double? gyroscopeY;
  final double? gyroscopeZ;
  final String deviceModel;
  final String platform;
  final DateTime timestamp;

  SensorData({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.speed,
    this.heading,
    this.accelerationX,
    this.accelerationY,
    this.accelerationZ,
    this.gyroscopeX,
    this.gyroscopeY,
    this.gyroscopeZ,
    required this.deviceModel,
    required this.platform,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'acceleration_x': accelerationX,
      'acceleration_y': accelerationY,
      'acceleration_z': accelerationZ,
      'gyroscope_x': gyroscopeX,
      'gyroscope_y': gyroscopeY,
      'gyroscope_z': gyroscopeZ,
      'device_model': deviceModel,
      'platform': platform,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class SensorService {
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<Position>? _positionSubscription;
  
  final List<SensorData> _sensorData = [];
  String? _deviceModel;
  String? _platform;

  Future<void> initialize() async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      _deviceModel = '${androidInfo.brand} ${androidInfo.model}';
      _platform = 'Android ${androidInfo.version.release}';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      _deviceModel = '${iosInfo.name} ${iosInfo.model}';
      _platform = 'iOS ${iosInfo.systemVersion}';
    }
  }

  void startSensorCollection() {
    // Start accelerometer data collection
    _accelerometerSubscription = accelerometerEvents.listen((AccelerometerEvent event) {
      _updateAccelerometerData(event.x, event.y, event.z);
    });

    // Start gyroscope data collection
    _gyroscopeSubscription = gyroscopeEvents.listen((GyroscopeEvent event) {
      _updateGyroscopeData(event.x, event.y, event.z);
    });

    // Start GPS data collection
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      ),
    ).listen((Position position) {
      _updatePositionData(position);
    });
  }

  void stopSensorCollection() {
    _accelerometerSubscription?.cancel();
    _gyroscopeSubscription?.cancel();
    _positionSubscription?.cancel();
  }

  void _updateAccelerometerData(double x, double y, double z) {
    final now = DateTime.now();
    final existingData = _sensorData.isNotEmpty ? _sensorData.last : null;
    
    if (existingData != null && 
        (now.difference(existingData.timestamp).inMilliseconds < 1000)) {
      // Update existing data if it's less than 1 second old
      final index = _sensorData.length - 1;
      _sensorData[index] = SensorData(
        latitude: existingData.latitude,
        longitude: existingData.longitude,
        accuracy: existingData.accuracy,
        speed: existingData.speed,
        heading: existingData.heading,
        accelerationX: x,
        accelerationY: y,
        accelerationZ: z,
        gyroscopeX: existingData.gyroscopeX,
        gyroscopeY: existingData.gyroscopeY,
        gyroscopeZ: existingData.gyroscopeZ,
        deviceModel: _deviceModel ?? 'Unknown',
        platform: _platform ?? 'Unknown',
        timestamp: now,
      );
    } else {
      // Create new data entry
      _sensorData.add(SensorData(
        accelerationX: x,
        accelerationY: y,
        accelerationZ: z,
        deviceModel: _deviceModel ?? 'Unknown',
        platform: _platform ?? 'Unknown',
        timestamp: now,
      ));
    }
  }

  void _updateGyroscopeData(double x, double y, double z) {
    final now = DateTime.now();
    final existingData = _sensorData.isNotEmpty ? _sensorData.last : null;
    
    if (existingData != null && 
        (now.difference(existingData.timestamp).inMilliseconds < 1000)) {
      // Update existing data if it's less than 1 second old
      final index = _sensorData.length - 1;
      _sensorData[index] = SensorData(
        latitude: existingData.latitude,
        longitude: existingData.longitude,
        accuracy: existingData.accuracy,
        speed: existingData.speed,
        heading: existingData.heading,
        accelerationX: existingData.accelerationX,
        accelerationY: existingData.accelerationY,
        accelerationZ: existingData.accelerationZ,
        gyroscopeX: x,
        gyroscopeY: y,
        gyroscopeZ: z,
        deviceModel: _deviceModel ?? 'Unknown',
        platform: _platform ?? 'Unknown',
        timestamp: now,
      );
    } else {
      // Create new data entry
      _sensorData.add(SensorData(
        gyroscopeX: x,
        gyroscopeY: y,
        gyroscopeZ: z,
        deviceModel: _deviceModel ?? 'Unknown',
        platform: _platform ?? 'Unknown',
        timestamp: now,
      ));
    }
  }

  void _updatePositionData(Position position) {
    final now = DateTime.now();
    final existingData = _sensorData.isNotEmpty ? _sensorData.last : null;
    
    if (existingData != null && 
        (now.difference(existingData.timestamp).inMilliseconds < 1000)) {
      // Update existing data if it's less than 1 second old
      final index = _sensorData.length - 1;
      _sensorData[index] = SensorData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        accelerationX: existingData.accelerationX,
        accelerationY: existingData.accelerationY,
        accelerationZ: existingData.accelerationZ,
        gyroscopeX: existingData.gyroscopeX,
        gyroscopeY: existingData.gyroscopeY,
        gyroscopeZ: existingData.gyroscopeZ,
        deviceModel: _deviceModel ?? 'Unknown',
        platform: _platform ?? 'Unknown',
        timestamp: now,
      );
    } else {
      // Create new data entry
      _sensorData.add(SensorData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        speed: position.speed,
        heading: position.heading,
        deviceModel: _deviceModel ?? 'Unknown',
        platform: _platform ?? 'Unknown',
        timestamp: now,
      ));
    }
  }

  List<Map<String, dynamic>> getSensorData() {
    return _sensorData.map((data) => data.toJson()).toList();
  }

  void clearSensorData() {
    _sensorData.clear();
  }

  int get dataCount => _sensorData.length;
}
