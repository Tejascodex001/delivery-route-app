import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'api_client.dart';

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
  final List<String> _addresses = [];
  List<LatLng> _ordered = [];
  List<LatLng> _polyline = [];
  bool _isLoading = false;
  final ImagePicker _picker = ImagePicker();

  // Local saved routes (simple in-memory). Each item is a list of addresses.
  final List<List<String>> _savedRoutes = [];

  void _saveCurrentRoute() {
    if (_addresses.isEmpty) return;
    setState(() {
      _savedRoutes.add(List<String>.from(_addresses));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Route saved')),
    );
  }

  void _clearCurrentRoute() {
    setState(() {
      _ordered = [];
      _polyline = [];
    });
  }

  Future<void> _plan() async {
    if (_addresses.isEmpty) return;
    setState(() {
      _isLoading = true;
    });
    try {
      print('Planning route for addresses: $_addresses');
      final res = await api.planFullRoute(addresses: _addresses);
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
      setState(() {
        _ordered = coords;
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
                  for (int i = 0; i < _ordered.length; i++)
                    Marker(
                      point: _ordered[i],
                      width: 36,
                      height: 36,
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: i == 0
                            ? Colors.green
                            : (i == _ordered.length - 1 ? Colors.red : Colors.orange),
                        child: Text('${i + 1}',
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
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
                // Search bar, pill style
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(28),
                  color: Theme.of(context).colorScheme.surface,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addrController,
                          decoration: InputDecoration(
                            hintText: 'Search or add address',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () {
                                final t = _addrController.text.trim();
                                if (t.isNotEmpty) {
                                  setState(() {
                                    _addresses.add(t);
                                    _addrController.clear();
                                  });
                                }
                              },
                            ),
                          ),
                          textAlign: TextAlign.center,
                          onSubmitted: (_) {
                            final t = _addrController.text.trim();
                            if (t.isNotEmpty) {
                              setState(() {
                                _addresses.add(t);
                                _addrController.clear();
                              });
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                // Actions row under search bar
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _plan,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.alt_route),
                        label: const Text('Plan'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addresses.isEmpty ? null : _saveCurrentRoute,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Save'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _addresses.clear();
                          });
                          _clearCurrentRoute();
                        },
                        child: const Text('Clear'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Address chips with individual X to remove
                if (_addresses.isNotEmpty)
                  SizedBox(
                    height: 44,
                    width: double.infinity,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _addresses.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => InputChip(
                        label: Text('${i + 1}. ${_addresses[i]}'),
                        onDeleted: () {
                          setState(() {
                            _addresses.removeAt(i);
                          });
                          _clearCurrentRoute();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom nav button
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              child: ElevatedButton.icon(
                onPressed: _ordered.length >= 2 ? _openExternalNav : null,
                icon: const Icon(Icons.navigation),
                label: const Text('Start Navigation (Google Maps)'),
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

  void _toggleTheme(bool isDark) {
    setState(() {
      _mode = isDark ? ThemeMode.dark : ThemeMode.light;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: _mode,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.light, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.teal, brightness: Brightness.dark, useMaterial3: true),
      home: MapScreen(),
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
