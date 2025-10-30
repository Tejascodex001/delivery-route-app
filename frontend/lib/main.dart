import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'api_client.dart';
import 'auth/sign_in.dart';
import 'auth/sign_up.dart';
import 'auth/verify_email.dart';
import 'services/db.dart';
import 'services/location_service.dart';
import 'services/sensor_service.dart';
import 'services/training_data_service.dart';
import 'backend_config_screen.dart';
import 'config.dart';
import 'utils/error_handler.dart';

class MapScreen extends StatefulWidget {
  final void Function()? onOpenSavedRoutes;
  final void Function()? onOpenSettings;
  final void Function()? onOpenAbout;
  const MapScreen({super.key, this.onOpenSavedRoutes, this.onOpenSettings, this.onOpenAbout});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Dynamic backend detection
  final api = const ApiClient();
  final mapController = MapController();
  final TextEditingController _addrController = TextEditingController();
  final FocusNode _addrFocus = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _nearbyPlaces = [];
  final List<String> _addresses = [];
  List<LatLng> _ordered = [];
  List<LatLng> _polyline = [];
  List<String> _orderedAddresses = []; // Track optimized order of addresses
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  LatLng? _currentLocation;
  bool _showCurrentLocation = false;
  
  // Training data and sensor collection
  final SensorService _sensorService = SensorService();
  final TrainingDataService _trainingService = TrainingDataService();
  String? _currentRouteId;
  DateTime? _routeStartTime;
  double? _predictedEtaMinutes;

  // Local saved routes with detailed information
  final List<Map<String, dynamic>> _savedRoutes = [];

  @override
  void initState() {
    super.initState();
    _loadSavedRoutesFromCSV(); // Load saved routes from CSV
    _addrFocus.addListener(() {
      if (_addrFocus.hasFocus) {
        // Load nearby places when search bar gains focus
        _loadNearbyPlaces();
      } else {
        // Clear suggestions when search bar loses focus
        setState(() {
          _suggestions = [];
          _nearbyPlaces = [];
        });
      }
    });
    _initializeServices();
    _ensureLocationOnStartup();
  }

  Future<void> _initializeServices() async {
    await _sensorService.initialize();
    _sensorService.startSensorCollection();
  }

  Future<void> _ensureLocationOnStartup() async {
    // Run after first frame to ensure context is ready
    await Future.delayed(const Duration(milliseconds: 100));
    final enabled = await LocationService.isLocationEnabled();
    var permission = await LocationService.checkPermission();
    if (!enabled) {
      final opened = await LocationService.openLocationSettings();
      if (opened) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    if (permission == LocationPermission.denied) {
      permission = await LocationService.requestPermission();
    }
    if (!mounted) return;
    // Try to fetch and center once available
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (pos != null) {
      setState(() {
        _currentLocation = LatLng(pos.latitude, pos.longitude);
        _showCurrentLocation = true;
      });
      mapController.move(_currentLocation!, 15.0);
    }
  }

  void _saveCurrentRoute() {
    if (_addresses.isEmpty) return;
    _showSaveRouteDialog();
  }

  void _showSaveRouteDialog() {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController descriptionController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.save_alt, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Save Route'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Route Name',
                hintText: 'e.g., Daily Delivery Route',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                hintText: 'Add notes about this route...',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Route Summary',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('${_addresses.length} stops'),
                  if (_predictedEtaMinutes != null)
                    Text('ETA: ${_predictedEtaMinutes!.toStringAsFixed(0)} minutes'),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a route name')),
                );
                return;
              }
              _saveRouteWithDetails(
                nameController.text.trim(),
                descriptionController.text.trim(),
              );
              Navigator.pop(context);
            },
            icon: const Icon(Icons.save),
            label: const Text('Save Route'),
          ),
        ],
      ),
    );
  }

  void _saveRouteWithDetails(String name, String description) {
    final routeData = {
      'name': name,
      'description': description,
      'addresses': List<String>.from(_addresses),
      'eta': _predictedEtaMinutes,
      'timestamp': DateTime.now().toIso8601String(),
      'coordinates': _ordered.map((coord) => {'lat': coord.latitude, 'lng': coord.longitude}).toList(),
    };
    
    setState(() {
      _savedRoutes.add(routeData);
    });
    
    // Save to CSV file
    _saveRouteToCSV(routeData);
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Route "$name" saved successfully!'),
        action: SnackBarAction(
          label: 'View',
          onPressed: () => _openSavedRoutesPage(),
        ),
      ),
    );
  }

  Future<void> _saveRouteToCSV(Map<String, dynamic> routeData) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/saved_routes.csv');
      
      List<List<dynamic>> csvData = [];
      
      // If file exists, read existing data
      if (await file.exists()) {
        final existingContent = await file.readAsString();
        csvData = const CsvToListConverter().convert(existingContent);
      } else {
        // Add header row for new file
        csvData.add(['Name', 'Description', 'Addresses', 'ETA (minutes)', 'Timestamp', 'Coordinates']);
      }
      
      // Add new route data
      csvData.add([
        routeData['name'],
        routeData['description'],
        (routeData['addresses'] as List).join('; '),
        routeData['eta']?.toString() ?? '',
        routeData['timestamp'],
        (routeData['coordinates'] as List).map((coord) => '${coord['lat']},${coord['lng']}').join('; '),
      ]);
      
      // Write to file
      final csvString = const ListToCsvConverter().convert(csvData);
      await file.writeAsString(csvString);
      
      print('Route saved to CSV: ${file.path}');
    } catch (e) {
      print('Error saving route to CSV: $e');
    }
  }

  Future<void> _loadSavedRoutesFromCSV() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/saved_routes.csv');
      
      if (await file.exists()) {
        final content = await file.readAsString();
        final csvData = const CsvToListConverter().convert(content);
        
        setState(() {
          _savedRoutes.clear();
          // Skip header row
          for (int i = 1; i < csvData.length; i++) {
            final row = csvData[i];
            if (row.length >= 6) {
              _savedRoutes.add({
                'name': row[0],
                'description': row[1],
                'addresses': (row[2] as String).split('; '),
                'eta': double.tryParse(row[3].toString()),
                'timestamp': row[4],
                'coordinates': (row[5] as String).split('; ').map((coord) {
                  final parts = coord.split(',');
                  if (parts.length == 2) {
                    return {
                      'lat': double.tryParse(parts[0]) ?? 0.0,
                      'lng': double.tryParse(parts[1]) ?? 0.0,
                    };
                  }
                  return {'lat': 0.0, 'lng': 0.0};
                }).toList(),
              });
            }
          }
        });
      }
    } catch (e) {
      print('Error loading saved routes from CSV: $e');
    }
  }

  Future<void> _logout() async {
    await DatabaseProvider.instance.clearSession();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/signin');
    }
  }

  Future<void> _getCurrentLocation() async {
    final position = await LocationService.getCurrentPosition();
    if (position != null) {
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _showCurrentLocation = true;
      });
      mapController.move(_currentLocation!, 15.0);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to get current location')),
      );
    }
  }

  void _clearCurrentRoute() {
    setState(() {
      _ordered = [];
      _polyline = [];
      _orderedAddresses = [];
      _predictedEtaMinutes = null;
    });
    _currentRouteId = null;
    _routeStartTime = null;
  }

  Future<void> _submitTrainingData(Map<String, dynamic> routeResponse, List<LatLng> coords, List<String> orderedAddrs) async {
    if (_currentRouteId == null || _routeStartTime == null) return;
    
    try {
      final coordinates = coords.map((c) => [c.latitude, c.longitude]).toList();
      final sensorData = _sensorService.getSensorData();
      
      final trainingData = TrainingData(
        routeId: _currentRouteId!,
        addresses: orderedAddrs,
        coordinates: coordinates,
        predictedEtaMinutes: _predictedEtaMinutes ?? 0.0,
        startTime: _routeStartTime!.toIso8601String(),
        sensorData: sensorData,
        userId: 'user_${DateTime.now().millisecondsSinceEpoch}', // Simple user ID for now
        routeMetadata: {
          'total_distance_km': routeResponse['total_distance_km'] ?? 0.0,
          'ors_duration_minutes': routeResponse['ors_duration_minutes'] ?? 0.0,
          'num_stops': routeResponse['num_stops'] ?? 0,
          'device_info': {
            'platform': Platform.operatingSystem,
            'version': Platform.operatingSystemVersion,
          }
        },
      );
      
      await _trainingService.submitTrainingData(trainingData);
      print('✅ Training data submitted for route $_currentRouteId');
    } catch (e) {
      print('❌ Error submitting training data: $e');
    }
  }

  String _formatEta(double minutes) {
    if (minutes < 60) {
      return '${minutes.round()} min';
    } else {
      final hours = (minutes / 60).floor();
      final remainingMinutes = (minutes % 60).round();
      if (remainingMinutes == 0) {
        return '${hours}h';
      } else {
        return '${hours}h ${remainingMinutes}m';
      }
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Scan Address'),
          content: const Text('Choose how you want to add the address:'),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _pickImageFromCamera();
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Take Photo'),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                _pickImageFromGallery();
              },
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose from Gallery'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _pickImageFromCamera() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );
      if (image != null) {
        await _processImage(File(image.path));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Camera error: $e')),
      );
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
      );
      if (image != null) {
        await _processImage(File(image.path));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gallery error: $e')),
      );
    }
  }

  Future<void> _processImage(File imageFile) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final result = await api.extractTextFromImage(imageFile);
      final extractedText = result['extracted_text'] as String?;
      
      if (extractedText != null && extractedText.isNotEmpty) {
        // Show extracted text and let user confirm
        final confirmed = await _showExtractedTextDialog(extractedText);
        if (confirmed) {
          setState(() {
            _addresses.add(extractedText);
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No text found in the image')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR error: $e')),
      );
    } finally {
      if (mounted) setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _showExtractedTextDialog(String extractedText) async {
    return await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Extracted Address'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('We found this address:'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  extractedText,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 8),
              const Text('Would you like to add this address?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add Address'),
            ),
          ],
        );
      },
    ) ?? false;
  }

  IconData _getAmenityIcon(String amenity) {
    switch (amenity) {
      case 'restaurant':
        return Icons.restaurant;
      case 'hospital':
        return Icons.local_hospital;
      case 'school':
        return Icons.school;
      case 'university':
        return Icons.account_balance;
      case 'bank':
        return Icons.account_balance;
      case 'fuel':
        return Icons.local_gas_station;
      case 'parking':
        return Icons.local_parking;
      case 'pharmacy':
        return Icons.local_pharmacy;
      case 'post_office':
        return Icons.local_post_office;
      case 'police':
        return Icons.local_police;
      case 'fire_station':
        return Icons.local_fire_department;
      default:
        return Icons.place;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _addrFocus.dispose();
    _addrController.dispose();
    _sensorService.stopSensorCollection();
    super.dispose();
  }

  Future<void> _loadNearbyPlaces() async {
    if (_currentLocation == null) return;
    
    try {
      final places = await api.getNearbyPlaces(
        _currentLocation!.latitude, 
        _currentLocation!.longitude,
        radius: 3000, // 3km radius
      );
      setState(() {
        _nearbyPlaces = places;
      });
    } catch (e) {
      print('Nearby places error: $e');
      setState(() => _nearbyPlaces = []);
      // Show user-friendly error message
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, 'Failed to load nearby places: ${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async { // Reduced from 350ms
      final q = text.trim();
      if (q.isEmpty || q.length < 2) {
        setState(() => _suggestions = []);
        return;
      }
      try {
        // Use backend API for secure search suggestions
        final suggestions = await api.searchSuggestions(q);
        setState(() => _suggestions = suggestions);
      } catch (e) {
        print('Search error: $e');
        setState(() => _suggestions = []);
        // Show user-friendly error message
        if (mounted) {
          ErrorHandler.showErrorSnackBar(context, 'Search failed: ${e.toString().replaceFirst('Exception: ', '')}');
        }
      }
    });
  }

  Future<bool> _ensureLocationInteractive() async {
    final enabled = await LocationService.isLocationEnabled();
    if (!enabled) {
      final opened = await LocationService.openLocationSettings();
      if (!opened) return false;
      await Future.delayed(const Duration(seconds: 1));
    }
    var permission = await LocationService.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await LocationService.requestPermission();
    }
    return permission == LocationPermission.always || permission == LocationPermission.whileInUse;
  }

  Future<void> _plan() async {
    if (_addresses.isEmpty) return;
    setState(() {
      _isLoading = true;
    });
    try {
      // Get current location first
      final currentPos = await LocationService.getCurrentPosition();
      if (currentPos == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to get current location')),
        );
        return;
      }

      // Use actual coordinates for current location - ALWAYS FIRST
      final currentLocationString = '${currentPos.latitude},${currentPos.longitude}';
      final allAddresses = [currentLocationString, ..._addresses];
      
      print('Planning route for addresses: $allAddresses');
      print('Current location: ${currentPos.latitude}, ${currentPos.longitude}');
      print('Total addresses: ${allAddresses.length}');
      
      final res = await api.planFullRoute(
        addresses: allAddresses,
        vehicleStartAddress: currentLocationString,
      );
      print('Backend response: $res');
      
      if (res['ordered_coordinates'] == null || (res['ordered_coordinates'] as List).isEmpty) {
        print('No coordinates returned from backend');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ Could not find coordinates for the addresses. Try using more specific locations or well-known landmarks.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
      
      final coords = (res['ordered_coordinates'] as List)
          .map((e) => LatLng((e[0] as num).toDouble(), (e[1] as num).toDouble()))
          .toList();
      final orderedAddrs = List<String>.from(res['ordered_addresses'] ?? []);
      final predictedEta = res['predicted_eta_minutes'] as double?;
      
      print('Ordered addresses from backend: $orderedAddrs');
      print('Ordered coordinates: $coords');
      print('Predicted ETA: $predictedEta minutes');
      print('First coordinate (should be current location): ${coords.isNotEmpty ? coords.first : "None"}');
      
      // Generate route ID and start data collection
      _currentRouteId = _trainingService.generateRouteId();
      _routeStartTime = DateTime.now();
      _predictedEtaMinutes = predictedEta;
      
      // Submit initial training data
      await _submitTrainingData(res, coords, orderedAddrs);
      
      setState(() {
        _ordered = coords;
        _orderedAddresses = orderedAddrs;
        _polyline = _decodeGeoJsonLineString(res['route_geometry_geojson']);
      });
      if (_ordered.isNotEmpty) {
        mapController.move(_ordered.first, 12);
      }
      print('Route planned successfully with ${_ordered.length} stops');
    } catch (e) {
      print('Error planning route: $e');
      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  List<LatLng> _decodeGeoJsonLineString(dynamic geojson) {
    if (geojson == null) return [];
    try {
      final geometry = geojson['geometry'];
      final type = geometry['type'];
      if (type == 'LineString') {
        final coords = geometry['coordinates'] as List;
        return coords
            .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<void> _openExternalNav() async {
    if (_ordered.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please plan a route first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(),
      ),
    );

    try {
      final origin = _ordered.first;
      final dest = _ordered.last;
      final waypoints = _ordered
          .skip(1)
          .take(_ordered.length - 2)
          .map((p) => '${p.latitude},${p.longitude}')
          .join('|');
      
      // Enhanced Google Maps URLs with better formatting
      final urls = [
        // Google Maps app (preferred - most reliable)
        'comgooglemaps://?daddr=${dest.latitude},${dest.longitude}&saddr=${origin.latitude},${origin.longitude}${waypoints.isNotEmpty ? '&waypoints=$waypoints' : ''}',
        
        // Google Maps web with optimized parameters
        'https://www.google.com/maps/dir/?api=1&origin=${origin.latitude},${origin.longitude}&destination=${dest.latitude},${dest.longitude}' +
            (waypoints.isNotEmpty ? '&waypoints=$waypoints' : '') +
            '&travelmode=driving&dir_action=navigate',
        
        // Alternative: Apple Maps (for iOS)
        'http://maps.apple.com/?daddr=${dest.latitude},${dest.longitude}&saddr=${origin.latitude},${origin.longitude}',
        
        // Fallback: OpenStreetMap
        'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=${origin.latitude},${origin.longitude};${dest.latitude},${dest.longitude}',
      ];
      
      bool launched = false;
      String? launchedApp;
      
      for (int i = 0; i < urls.length; i++) {
        try {
          final uri = Uri.parse(urls[i]);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            launched = true;
            
            // Determine which app was launched
            if (i == 0) launchedApp = 'Google Maps App';
            else if (i == 1) launchedApp = 'Google Maps Web';
            else if (i == 2) launchedApp = 'Apple Maps';
            else launchedApp = 'OpenStreetMap';
            
            break;
          }
        } catch (e) {
          print('Failed to launch ${urls[i]}: $e');
          continue;
        }
      }
      
      // Close loading dialog
      Navigator.of(context).pop();
      
      if (launched) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🚗 Navigation opened in $launchedApp'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        // Show manual navigation options
        _showNavigationOptions(origin, dest, waypoints);
      }
    } catch (e) {
      // Close loading dialog
      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening navigation: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showNavigationOptions(LatLng origin, LatLng dest, String waypoints) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Navigation Options'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose your preferred navigation app:'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.map, color: Colors.blue),
              title: const Text('Google Maps'),
              subtitle: const Text('Open in browser'),
              onTap: () {
                Navigator.pop(context);
                _launchGoogleMapsWeb(origin, dest, waypoints);
              },
            ),
            ListTile(
              leading: const Icon(Icons.navigation, color: Colors.green),
              title: const Text('Apple Maps'),
              subtitle: const Text('iOS Maps app'),
              onTap: () {
                Navigator.pop(context);
                _launchAppleMaps(origin, dest);
              },
            ),
            ListTile(
              leading: const Icon(Icons.public, color: Colors.orange),
              title: const Text('OpenStreetMap'),
              subtitle: const Text('Open source maps'),
              onTap: () {
                Navigator.pop(context);
                _launchOpenStreetMap(origin, dest);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _launchGoogleMapsWeb(LatLng origin, LatLng dest, String waypoints) async {
    final url = 'https://www.google.com/maps/dir/?api=1&origin=${origin.latitude},${origin.longitude}&destination=${dest.latitude},${dest.longitude}' +
        (waypoints.isNotEmpty ? '&waypoints=$waypoints' : '') +
        '&travelmode=driving&dir_action=navigate';
    
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open Google Maps: $e')),
      );
    }
  }

  Future<void> _launchAppleMaps(LatLng origin, LatLng dest) async {
    final url = 'http://maps.apple.com/?daddr=${dest.latitude},${dest.longitude}&saddr=${origin.latitude},${origin.longitude}';
    
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open Apple Maps: $e')),
      );
    }
  }

  Future<void> _launchOpenStreetMap(LatLng origin, LatLng dest) async {
    final url = 'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=${origin.latitude},${origin.longitude};${dest.latitude},${dest.longitude}';
    
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open OpenStreetMap: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _ordered.length >= 2
          ? FloatingActionButton.extended(
              onPressed: _openExternalNav,
              icon: const Icon(Icons.navigation),
              label: const Text('Navigate'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            )
          : null,
      appBar: AppBar(
        title: const Text('ZipRoute'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          // Network status indicator
          FutureBuilder<Map<String, dynamic>>(
            future: ApiConfig.getNetworkInfo(),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                final info = snapshot.data!;
                final isProduction = info['is_production'] == true;
                return Tooltip(
                  message: 'Backend: ${info['backend_url']}\nMode: ${isProduction ? 'Production' : 'Development'}',
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isProduction ? Colors.green : Colors.blue,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isProduction ? Icons.cloud : Icons.router,
                          size: 12,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isProduction ? 'PROD' : 'DEV',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ListTile(title: Text('Menu', style: TextStyle(fontWeight: FontWeight.bold))),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.map),
                title: const Text('Plan Route'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading: const Icon(Icons.folder_copy),
                title: const Text('Saved Routes'),
                onTap: () {
                  Navigator.pop(context);
                  _openSavedRoutesPage();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('Settings'),
                onTap: () {
                  Navigator.pop(context);
                  _openSettings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.router),
                title: const Text('Backend Config'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const BackendConfigScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('About'),
                onTap: () {
                  Navigator.pop(context);
                  _openAbout();
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Logout', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  _logout();
                },
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Map as background
          Positioned.fill(
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: const LatLng(19.0760, 72.8777), // Mumbai default
                initialZoom: 11,
              ),
              children: [
                // Default light theme tiles for reliability
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.delivery_route_frontend',
                ),
                PolylineLayer(polylines: [
                  if (_polyline.isNotEmpty)
                    Polyline(
                      points: _polyline, 
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.white.withValues(alpha: 0.3) 
                          : Colors.black.withValues(alpha: 0.25), 
                      strokeWidth: 9
                    ),
                  if (_polyline.isNotEmpty)
                    Polyline(
                      points: _polyline, 
                      color: Theme.of(context).brightness == Brightness.dark 
                          ? Colors.cyan 
                          : Theme.of(context).colorScheme.primary, 
                      strokeWidth: 6
                    ),
                ]),
                MarkerLayer(markers: [
                  // Current location marker (Google Maps style)
                  if (_showCurrentLocation && _currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withValues(alpha: 0.3),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  // Route markers - always start from current location (1)
                  for (int i = 0; i < _ordered.length; i++)
                    Marker(
                      point: _ordered[i],
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: i == 0
                              ? Colors.green
                              : (i == _ordered.length - 1 ? Colors.red : Colors.orange),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ],
            ),
          ),

          // Top overlay: Google Maps-like search bar and actions below
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                // Material 3 Search bar with custom styling
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SearchBar(
                    controller: _addrController,
                    focusNode: _addrFocus,
                    hintText: 'Search or add address',
                    hintStyle: WidgetStatePropertyAll(
                      TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                    leading: Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                            trailing: [
                              IconButton(
                                icon: Icon(
                                  Icons.camera_alt,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                tooltip: 'Scan Address',
                                onPressed: _showImageSourceDialog,
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.my_location,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                tooltip: 'My Location',
                                onPressed: () async {
                                  final ok = await _ensureLocationInteractive();
                                  if (!ok) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please enable location services.')),
                                    );
                                    return;
                                  }
                                  await _getCurrentLocation();
                                },
                              ),
                            ],
                    backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
                    elevation: const WidgetStatePropertyAll(0.0),
                    onChanged: (value) {
                      _onSearchChanged(value);
                    },
                    onSubmitted: (value) {
                      final t = value.trim();
                      if (t.isNotEmpty) {
                        setState(() {
                          _addresses.add(t);
                          _addrController.clear();
                          _suggestions = [];
                        });
                      }
                    },
                  ),
                ),
                        // Suggestions dropdown with scrolling
                        if (_addrFocus.hasFocus && (_suggestions.isNotEmpty || _nearbyPlaces.isNotEmpty))
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            constraints: const BoxConstraints(maxHeight: 300), // Limit height for scrolling
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Nearby places section
                                  if (_nearbyPlaces.isNotEmpty && _addrController.text.isEmpty)
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Text(
                                            'Nearby Places',
                                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                              color: Theme.of(context).colorScheme.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        ListView.separated(
                                          shrinkWrap: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          itemCount: _nearbyPlaces.length,
                                          separatorBuilder: (_, __) => const Divider(height: 1),
                                          itemBuilder: (context, index) {
                                            final place = _nearbyPlaces[index];
                                            return ListTile(
                                              leading: Icon(_getAmenityIcon(place['amenity'])),
                                              title: Text(
                                                place['name'] as String,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              subtitle: Text(
                                                place['amenity'].toString().replaceAll('_', ' ').toUpperCase(),
                                                style: Theme.of(context).textTheme.bodySmall,
                                              ),
                                              onTap: () {
                                                setState(() {
                                                  _addresses.add(place['display_name'] as String);
                                                  _addrController.clear();
                                                  _addrFocus.unfocus();
                                                  _suggestions = [];
                                                  _nearbyPlaces = [];
                                                });
                                              },
                                            );
                                          },
                                        ),
                                        if (_suggestions.isNotEmpty) const Divider(),
                                      ],
                                    ),
                                  // Search suggestions section
                                  if (_suggestions.isNotEmpty)
                                    ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: _suggestions.length,
                                      separatorBuilder: (_, __) => const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final s = _suggestions[index];
                                        return ListTile(
                                          leading: const Icon(Icons.place_outlined),
                                          title: Text(
                                            s['display_name'] as String,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          onTap: () {
                                            final display = s['display_name'] as String;
                                            setState(() {
                                              _addresses.add(display);
                                              _addrController.clear();
                                              _addrFocus.unfocus();
                                              _suggestions = [];
                                              _nearbyPlaces = [];
                                            });
                                          },
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                const SizedBox(height: 10),
                // Modern Action buttons with consistent sizing
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isLoading
                            ? null
                            : () async {
                                final ok = await _ensureLocationInteractive();
                                if (!ok) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Please enable location to plan route.')),
                                  );
                                  return;
                                }
                                await _plan();
                              },
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.alt_route, size: 18),
                        label: const Text('Plan'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addresses.isEmpty ? null : _saveCurrentRoute,
                        icon: const Icon(Icons.bookmark_add, size: 18),
                        label: const Text('Save'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _addresses.clear();
                          });
                          _clearCurrentRoute();
                        },
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('Clear'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Material 3 Address chips - show optimized order
                if (_addresses.isNotEmpty)
                  SizedBox(
                    height: 44,
                    width: double.infinity,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _addresses.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        // Show entry order before planning, optimized order after planning
                        final address = _addresses[i];
                        int displayNumber;
                        Color chipColor;
                        
                        if (_orderedAddresses.isNotEmpty) {
                          // After planning: show optimized order
                          final optimizedIndex = _orderedAddresses.indexOf(address);
                          if (optimizedIndex >= 0) {
                            displayNumber = optimizedIndex + 1;
                            chipColor = optimizedIndex == 0 
                                ? Colors.green 
                                : (optimizedIndex == _orderedAddresses.length - 1 
                                    ? Colors.red 
                                    : Colors.orange);
                          } else {
                            displayNumber = i + 1;
                            chipColor = Colors.grey;
                          }
                        } else {
                          // Before planning: show entry order
                          displayNumber = i + 1;
                          chipColor = Colors.blue;
                        }
                        
                        return ActionChip(
                          label: Text(
                            address,
                            style: const TextStyle(fontSize: 12),
                          ),
                          avatar: CircleAvatar(
                            radius: 10,
                            backgroundColor: chipColor,
                            child: Text(
                              '$displayNumber',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          onPressed: () {
                            setState(() {
                              _addresses.removeAt(i);
                            });
                            _clearCurrentRoute();
                          },
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // ETA Display Card (Material You style)
          if (_predictedEtaMinutes != null)
            Positioned(
              top: 120,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.schedule,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'AI Predicted ETA',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _formatEta(_predictedEtaMinutes!),
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            setState(() {
                              _predictedEtaMinutes = null;
                            });
                          },
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (_ordered.isNotEmpty) ...[
                      const SizedBox(height: 16),
                        // Removed stretched navigation button - using only the floating action button
                        OutlinedButton.icon(
                          onPressed: () {
                            // Clear current route but keep addresses for adding more
                            setState(() {
                              _ordered = [];
                              _polyline = [];
                              _orderedAddresses = [];
                              _predictedEtaMinutes = null;
                            });
                            _currentRouteId = null;
                            _routeStartTime = null;
                          },
                          icon: const Icon(Icons.add_location, size: 18),
                          label: const Text('Add More Stops'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            minimumSize: const Size(double.infinity, 44),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Quick navigation info
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Tap "Navigate" to open in Google Maps with turn-by-turn directions',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),

          // Bottom nav button (fallback if no ETA)
          if (_ordered.isNotEmpty && _predictedEtaMinutes == null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                child: FilledButton.icon(
                  onPressed: _ordered.length >= 2 ? _openExternalNav : null,
                  icon: const Icon(Icons.navigation, size: 18),
                  label: const Text('Start Navigation'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PreferencesScreen extends StatefulWidget {
  const PreferencesScreen({super.key});

  @override
  State<PreferencesScreen> createState() => _PreferencesScreenState();
}

class _PreferencesScreenState extends State<PreferencesScreen> {
  bool _isDarkTheme = false;
  bool _dataCollectionEnabled = false;
  bool _locationTrackingEnabled = true;
  bool _sensorDataEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    // Load data collection preferences from SharedPreferences
    final prefs = await DatabaseProvider.instance.getPreferences();
    setState(() {
      // Always use the stored preference, not the current theme
      _isDarkTheme = prefs['isDarkTheme'] ?? false;
      _dataCollectionEnabled = prefs['dataCollectionEnabled'] ?? false;
      _locationTrackingEnabled = prefs['locationTrackingEnabled'] ?? true;
      _sensorDataEnabled = prefs['sensorDataEnabled'] ?? false;
    });
  }

  Future<void> _savePreferences() async {
    await DatabaseProvider.instance.savePreferences({
      'isDarkTheme': _isDarkTheme,
      'dataCollectionEnabled': _dataCollectionEnabled,
      'locationTrackingEnabled': _locationTrackingEnabled,
      'sensorDataEnabled': _sensorDataEnabled,
    });
  }

  void _toggleTheme() async {
    setState(() {
      _isDarkTheme = !_isDarkTheme;
    });
    // Save immediately for persistence
    await _savePreferences();
    // Find the MyApp state and toggle theme
    final state = context.findAncestorStateOfType<_MyAppState>();
    state?._toggleTheme(_isDarkTheme);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () async {
              await _savePreferences();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Preferences saved')),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Dark Theme'),
                    subtitle: const Text('Use dark theme for better visibility in low light'),
                    value: _isDarkTheme,
                    onChanged: (value) => _toggleTheme(),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Terms and Policy
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.policy,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Terms and Policy',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  ListTile(
                    leading: const Icon(Icons.description),
                    title: const Text('Terms of Service'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showTermsOfService(),
                  ),
                  
                  ListTile(
                    leading: const Icon(Icons.privacy_tip),
                    title: const Text('Privacy Policy'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showPrivacyPolicy(),
                  ),
                  
                  const Divider(),
                  
                  // Data Collection Preferences
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Data Collection Preferences',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Help us improve route optimization by sharing anonymous usage data',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        SwitchListTile(
                          title: const Text('Enable Data Collection'),
                          subtitle: const Text('Share anonymous route data for ML training'),
                          value: _dataCollectionEnabled,
                          onChanged: (value) {
                            setState(() {
                              _dataCollectionEnabled = value;
                            });
                          },
                        ),
                        
                        SwitchListTile(
                          title: const Text('Location Tracking'),
                          subtitle: const Text('Track location for route optimization'),
                          value: _locationTrackingEnabled,
                          onChanged: (value) {
                            setState(() {
                              _locationTrackingEnabled = value;
                            });
                          },
                        ),
                        
                        SwitchListTile(
                          title: const Text('Sensor Data'),
                          subtitle: const Text('Collect accelerometer and gyroscope data'),
                          value: _sensorDataEnabled,
                          onChanged: (value) {
                            setState(() {
                              _sensorDataEnabled = value;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Storage Management
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Storage Management',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Clear All Data'),
                    subtitle: const Text('Delete all saved routes and preferences'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showClearDataDialog(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Data'),
        content: const Text(
          'This will delete all saved routes, preferences, and CSV files. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              // Clear all data
              await DatabaseProvider.instance.clearAllData();
              if (mounted) {
                Navigator.pop(context);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All data cleared')),
                );
              }
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  void _showTermsOfService() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Terms of Service'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Last Updated: October 2025\n\n'
                '1. Acceptance of Terms\n'
                'By using ZipRoute, you agree to these Terms of Service. If you do not agree, please do not use the app.\n\n'
                '2. Use of Service\n'
                '• ZipRoute is provided for route optimization and delivery management\n'
                '• You must be at least 18 years old to use this service\n'
                '• You are responsible for maintaining account security\n\n'
                '3. User Responsibilities\n'
                '• Provide accurate information\n'
                '• Use the service lawfully and ethically\n'
                '• Do not misuse or attempt to hack the service\n\n'
                '4. Intellectual Property\n'
                '• All content and features are owned by ZipRoute\n'
                '• You may not copy, modify, or distribute our content\n\n'
                '5. Limitation of Liability\n'
                '• ZipRoute is provided "as is" without warranties\n'
                '• We are not liable for any damages from use of the service\n'
                '• Route suggestions are estimates and may not be optimal\n\n'
                '6. Termination\n'
                '• We may terminate or suspend access at any time\n'
                '• You may delete your account at any time\n\n'
                '7. Changes to Terms\n'
                '• We may update these terms at any time\n'
                '• Continued use constitutes acceptance of new terms',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyPolicy() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text(
                'Last Updated: October 2025\n\n'
                '1. Information We Collect\n'
                '• Account Information: Email and password (encrypted)\n'
                '• Location Data: GPS coordinates for route optimization (only when enabled)\n'
                '• Sensor Data: Accelerometer and gyroscope (only when enabled)\n'
                '• Route Data: Delivery addresses and route history\n\n'
                '2. How We Use Your Information\n'
                '• Route Optimization: Improve delivery route algorithms\n'
                '• Traffic Prediction: Analyze patterns for better ETA predictions\n'
                '• Service Improvement: Enhance app performance and features\n'
                '• ML Training: Train machine learning models (anonymized data only)\n\n'
                '3. Data Sharing\n'
                '• We DO NOT sell your personal information\n'
                '• We DO NOT share data with third parties for marketing\n'
                '• Anonymized data may be used for research purposes\n'
                '• We may share data if required by law\n\n'
                '4. Data Security\n'
                '• Passwords are encrypted using industry standards\n'
                '• Data transmission uses HTTPS encryption\n'
                '• We implement security measures to protect your data\n\n'
                '5. Data Retention\n'
                '• Account data is kept until you delete your account\n'
                '• Route history is kept for 90 days by default\n'
                '• You can delete all data anytime from settings\n\n'
                '6. Your Rights\n'
                '• Access your data anytime\n'
                '• Delete your data anytime\n'
                '• Disable data collection anytime\n'
                '• Export your data (coming soon)\n\n'
                '7. Children\'s Privacy\n'
                '• ZipRoute is not intended for users under 18\n'
                '• We do not knowingly collect data from children\n\n'
                '8. Changes to Privacy Policy\n'
                '• We may update this policy at any time\n'
                '• You will be notified of significant changes\n\n'
                'For questions, contact: support@ziproute.com',
                style: TextStyle(fontSize: 13, height: 1.5),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  ThemeMode _mode = ThemeMode.light;
  bool _isLoading = true;
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
    _loadThemePreference();
  }

  Future<void> _checkSession() async {
    final session = await DatabaseProvider.instance.getSession();
    setState(() {
      _isLoggedIn = session != null;
      _isLoading = false;
    });
  }

  Future<void> _loadThemePreference() async {
    final prefs = await DatabaseProvider.instance.getPreferences();
    final isDarkTheme = prefs['isDarkTheme'] ?? false;
    if (mounted) {
      setState(() {
        _mode = isDarkTheme ? ThemeMode.dark : ThemeMode.light;
      });
    }
  }

  void _toggleTheme(bool isDark) {
    setState(() {
      _mode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _mode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.light),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size(0, 44),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size(0, 44),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.grey.withOpacity(0.06),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.withOpacity(0.3)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
        chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        searchBarTheme: SearchBarThemeData(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.cyan, brightness: Brightness.dark),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size(0, 44),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            minimumSize: const Size(0, 44),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        ),
        chipTheme: ChipThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        searchBarTheme: SearchBarThemeData(
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(28))),
        ),
      ),
      routes: {
        '/signin': (_) => const SignInPage(),
        '/signup': (_) => const SignUpPage(),
        '/verify-email': (_) => const VerifyEmailPage(),
      },
      home: _isLoading 
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            )
          : _isLoggedIn 
              ? const MapScreen() 
              : const SignInPage(),
    );
  }
}

void main() {
  runApp(const MyApp());
}

// ------ Helpers: dialogs -------
extension _Dialogs on _MapScreenState {
  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const PreferencesScreen(),
      ),
    );
  }

  void _openAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'ZipRoute',
      applicationVersion: '1.0.0',
      applicationLegalese: 'Map data © OpenStreetMap contributors',
    );
  }

  void _openSavedRoutesPage() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SavedRoutesPage(
      savedRoutes: _savedRoutes,
      onDelete: (idx) => _deleteSavedRoute(idx),
      onLoad: (idx) => _loadSavedRoute(idx),
    )));
  }

  void _deleteSavedRoute(int idx) {
    setState(() {
      _savedRoutes.removeAt(idx);
    });
    _updateCSVFile(); // Update CSV file after deletion
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route deleted')),
    );
  }

  void _loadSavedRoute(int idx) {
    final route = _savedRoutes[idx];
    setState(() {
      _addresses.clear();
      _addresses.addAll(route['addresses'] as List<String>);
      _predictedEtaMinutes = route['eta'] as double?;
    });
    _clearCurrentRoute();
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Route "${route['name']}" loaded')),
    );
  }

  Future<void> _updateCSVFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/saved_routes.csv');
      
      List<List<dynamic>> csvData = [
        ['Name', 'Description', 'Addresses', 'ETA (minutes)', 'Timestamp', 'Coordinates']
      ];
      
      for (final route in _savedRoutes) {
        csvData.add([
          route['name'],
          route['description'],
          (route['addresses'] as List).join('; '),
          route['eta']?.toString() ?? '',
          route['timestamp'],
          (route['coordinates'] as List).map((coord) => '${coord['lat']},${coord['lng']}').join('; '),
        ]);
      }
      
      final csvString = const ListToCsvConverter().convert(csvData);
      await file.writeAsString(csvString);
    } catch (e) {
      print('Error updating CSV file: $e');
    }
  }

  // Unused method - commented out to fix linting
  /* Future<void> _pickAndUploadImage() async {
    final XFile? img = await _picker.pickImage(source: ImageSource.gallery);
    if (img == null) return;

    try {
      final file = File(img.path);
      final res = await api.extractTextFromImage(file);
      final text = res['extracted_text'] as String?;
      if (text == null || text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No text found in image')),
        );
        return;
      }
      // Heuristic split by newlines/semicolons
      final parts = text.split(RegExp(r'[\n;]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    setState(() {
        _addresses.addAll(parts);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('OCR failed: $e')),
      );
    }
  } */

  // Unused method - commented out to fix linting
  /* Future<void> _goToMyLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission permanently denied.')),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      setState(() {
        _current = LatLng(pos.latitude, pos.longitude);
      });
      mapController.move(_current!, 14);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location error: $e')),
      );
    }
  } */
}

class SavedRoutesPage extends StatelessWidget {
  final List<Map<String, dynamic>> savedRoutes;
  final void Function(int index) onDelete;
  final void Function(int index) onLoad;
  const SavedRoutesPage({super.key, required this.savedRoutes, required this.onDelete, required this.onLoad});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Routes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Refresh saved routes
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: savedRoutes.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route_outlined, size: 64, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
            Text(
                    'No saved routes yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Plan and save your first route to see it here',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
            ),
          ],
        ),
            )
          : ListView.separated(
              itemCount: savedRoutes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final route = savedRoutes[i];
                final addresses = route['addresses'] as List<String>;
                final name = route['name'] as String;
                final description = route['description'] as String;
                final eta = route['eta'] as double?;
                
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        Icons.route,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (description.isNotEmpty)
                          Text(
                            description,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                '${addresses.length} stops',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (eta != null) ...[
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${eta.toStringAsFixed(0)} min',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.upload),
                          tooltip: 'Load Route',
                          onPressed: () => onLoad(i),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: 'Delete Route',
                          onPressed: () => onDelete(i),
                        ),
                      ],
                    ),
                    onTap: () => onLoad(i),
                  ),
                );
              },
            ),
    );
  }
}

