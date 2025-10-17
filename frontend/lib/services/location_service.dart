import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  static Future<bool> isLocationEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  static Future<LocationPermission> checkPermission() async {
    return await Geolocator.checkPermission();
  }

  static Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  static Future<Position?> getCurrentPosition() async {
    try {
      final serviceEnabled = await isLocationEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('❌ Location error: $e');
      return null;
    }
  }

  static Future<LatLng?> getCurrentLatLng() async {
    final position = await getCurrentPosition();
    if (position == null) return null;
    return LatLng(position.latitude, position.longitude);
  }

  static String getPermissionStatusText(LocationPermission permission) {
    switch (permission) {
      case LocationPermission.always:
        return 'Location access granted (always)';
      case LocationPermission.whileInUse:
        return 'Location access granted (while in use)';
      case LocationPermission.denied:
        return 'Location access denied';
      case LocationPermission.deniedForever:
        return 'Location access permanently denied';
      case LocationPermission.unableToDetermine:
        return 'Unable to determine location permission';
    }
  }

  // Prompt user to enable location services in device settings
  static Future<bool> openLocationSettings() async {
    final opened = await Geolocator.openLocationSettings();
    return opened;
  }
}
