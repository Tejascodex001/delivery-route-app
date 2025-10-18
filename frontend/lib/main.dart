import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'auth/sign_in.dart';
import 'auth/sign_up.dart';
import 'auth/verify_email.dart';
import 'services/db.dart';
import 'services/location_service.dart';
import 'services/sensor_service.dart';
import 'services/training_data_service.dart';

class MapScreen extends StatefulWidget {
  final void Function()? onOpenSavedRoutes;
  final void Function()? onOpenSettings;
  final void Function()? onOpenAbout;
  const MapScreen({super.key, this.onOpenSavedRoutes, this.onOpenSettings, this.onOpenAbout});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Use your machine's actual IP address
  final api = const ApiClient(baseUrl: 'http://192.168.0.101:8000');
  final mapController = MapController();
  final TextEditingController _addrController = TextEditingController();
  final FocusNode _addrFocus = FocusNode();
  Timer? _debounce;
  List<Map<String, dynamic>> _suggestions = [];
  final List<String> _addresses = [];
  List<LatLng> _ordered = [];
  List<LatLng> _polyline = [];
  List<String> _orderedAddresses = []; // Track optimized order of addresses
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();
  LatLng? _current;
  LatLng? _currentLocation;
  bool _showCurrentLocation = false;
  
  // Training data and sensor collection
  final SensorService _sensorService = SensorService();
  final TrainingDataService _trainingService = TrainingDataService();
  String? _currentRouteId;
  DateTime? _routeStartTime;
  double? _predictedEtaMinutes;

  // Local saved routes (simple in-memory). Each item is a list of addresses.
  final List<List<String>> _savedRoutes = [];

  @override
  void initState() {
    super.initState();
    _addrFocus.addListener(() {
      if (!_addrFocus.hasFocus) {
        // Clear suggestions when search bar loses focus
        setState(() {
          _suggestions = [];
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
    setState(() {
      _savedRoutes.add(List<String>.from(_addresses));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route saved')),
    );
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

  @override
  void dispose() {
    _debounce?.cancel();
    _addrFocus.dispose();
    _addrController.dispose();
    _sensorService.stopSensorCollection();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
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
    if (_ordered.length < 2) return;
    final origin = _ordered.first;
    final dest = _ordered.last;
    final waypoints = _ordered
        .skip(1)
        .take(_ordered.length - 2)
        .map((p) => '${p.latitude},${p.longitude}')
        .join('|');
    
    // Try multiple navigation options
    final urls = [
      // Google Maps web
      'https://www.google.com/maps/dir/?api=1&origin=${origin.latitude},${origin.longitude}&destination=${dest.latitude},${dest.longitude}' +
          (waypoints.isNotEmpty ? '&waypoints=$waypoints' : '') +
          '&travelmode=driving',
      // Google Maps app (if installed)
      'comgooglemaps://?daddr=${dest.latitude},${dest.longitude}&saddr=${origin.latitude},${origin.longitude}',
      // Alternative: OpenStreetMap
      'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=${origin.latitude},${origin.longitude};${dest.latitude},${dest.longitude}',
    ];
    
    bool launched = false;
    for (final urlString in urls) {
      try {
        final uri = Uri.parse(urlString);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          launched = true;
          break;
        }
      } catch (e) {
        print('Failed to launch $urlString: $e');
        continue;
      }
    }
    
    if (!launched) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open navigation app. Please install Google Maps or use a web browser.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Route Optimizer')),
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
              ListTile(
                leading: const Icon(Icons.document_scanner),
                title: const Text('Import via OCR'),
                onTap: () async {
                  Navigator.pop(context);
                  await _pickAndUploadImage();
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
                // High-contrast tiles with POIs and labels; force light @2x for readability
                TileLayer(
                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}@2x.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.example.delivery_route_frontend',
                ),
                PolylineLayer(polylines: [
                  if (_polyline.isNotEmpty)
                    Polyline(points: _polyline, color: Colors.black.withOpacity(0.25), strokeWidth: 9),
                  if (_polyline.isNotEmpty)
                    Polyline(points: _polyline, color: Theme.of(context).colorScheme.primary, strokeWidth: 6),
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
                              color: Colors.blue.withOpacity(0.3),
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
                              color: Colors.black.withOpacity(0.2),
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
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: SearchBar(
                    controller: _addrController,
                    focusNode: _addrFocus,
                    hintText: 'Search or add address',
                    hintStyle: MaterialStateProperty.all(
                      TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6)),
                    ),
                    leading: Icon(
                      Icons.search,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    trailing: [
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
                    backgroundColor: MaterialStateProperty.all(Colors.transparent),
                    elevation: MaterialStateProperty.all(0),
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
                // Suggestions dropdown
                if (_suggestions.isNotEmpty && _addrFocus.hasFocus)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
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
                    child: ListView.separated(
                      shrinkWrap: true,
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
                            });
                          },
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 10),
                // Material 3 Action buttons
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Theme.of(context).colorScheme.onPrimary,
                        ),
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
                            : const Icon(Icons.alt_route),
                        label: const Text('Plan Route'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addresses.isEmpty ? null : _saveCurrentRoute,
                        icon: const Icon(Icons.bookmark_add),
                        label: const Text('Save'),
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
                        icon: const Icon(Icons.clear_all),
                        label: const Text('Clear'),
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
                            radius: 8,
                            backgroundColor: chipColor,
                            child: Text(
                              '$displayNumber',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
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
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _openExternalNav,
                              icon: const Icon(Icons.navigation),
                              label: const Text('Start Navigation'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
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
                              icon: const Icon(Icons.add_location),
                              label: const Text('Add More'),
                            ),
                          ),
                        ],
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
                  icon: const Icon(Icons.navigation),
                  label: const Text('Start Navigation'),
                ),
              ),
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
  }

  Future<void> _checkSession() async {
    final session = await DatabaseProvider.instance.getSession();
    setState(() {
      _isLoggedIn = session != null;
      _isLoading = false;
    });
  }

  void _toggleTheme(bool isDark) {
    setState(() {
      _mode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: _mode,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        // Material You components
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        searchBarTheme: SearchBarThemeData(
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          ),
        ),
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.cyan,
        brightness: Brightness.dark,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        // Material You components
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        searchBarTheme: SearchBarThemeData(
          shape: MaterialStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          ),
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
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Settings'),
          content: StatefulBuilder(
            builder: (ctx, setS) => Row(
              children: [
                const Text('Dark theme'),
                const SizedBox(width: 12),
                Switch(
                  value: isDark,
                  onChanged: (v) {
                    isDark = v;
                    // Bubble up via finding MyApp state
                    final state = context.findAncestorStateOfType<_MyAppState>();
                    state?._toggleTheme(v);
                    setS(() {});
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ],
        );
      },
    );
  }

  void _openAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Delivery Route Optimizer',
      applicationVersion: '1.0.0',
      applicationLegalese: 'Map data © OpenStreetMap contributors',
    );
  }

  void _openSavedRoutesPage() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SavedRoutesPage(
      savedRoutes: _savedRoutes,
      onDelete: (idx) {
        setState(() {
          _savedRoutes.removeAt(idx);
        });
      },
      onLoad: (idx) {
        setState(() {
          _addresses
            ..clear()
            ..addAll(_savedRoutes[idx]);
        });
        _clearCurrentRoute();
        Navigator.pop(context);
      },
    )));
  }

  Future<void> _pickAndUploadImage() async {
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
  }

  Future<void> _goToMyLocation() async {
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
  }
}

class SavedRoutesPage extends StatelessWidget {
  final List<List<String>> savedRoutes;
  final void Function(int index) onDelete;
  final void Function(int index) onLoad;
  const SavedRoutesPage({super.key, required this.savedRoutes, required this.onDelete, required this.onLoad});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Routes')),
      body: savedRoutes.isEmpty
          ? const Center(child: Text('No saved routes yet'))
          : ListView.separated(
              itemCount: savedRoutes.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) => ListTile(
                leading: const Icon(Icons.route),
                title: Text(savedRoutes[i].join('  →  '), maxLines: 2, overflow: TextOverflow.ellipsis),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.download),
                      tooltip: 'Export',
                      onPressed: () {
                        final content = savedRoutes[i].join('\n');
                        // For now: show a dialog with copyable content. (File export would require storage permissions.)
                        showDialog(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Export Route'),
                            content: SingleChildScrollView(child: SelectableText(content)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                            ],
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.upload),
                      tooltip: 'Load',
                      onPressed: () => onLoad(i),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => onDelete(i),
                    ),
                  ],
                ),
                onTap: () => onLoad(i),
              ),
            ),
    );
  }
}
