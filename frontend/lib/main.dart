import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_client.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  // Use your machine's actual IP address
  final api = const ApiClient(baseUrl: 'http://192.168.0.103:8000');
  final mapController = MapController();
  final TextEditingController _addrController = TextEditingController();
  final List<String> _addresses = [];
  List<LatLng> _ordered = [];
  List<LatLng> _polyline = [];
  bool _isLoading = false;

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _addrController,
                    decoration: const InputDecoration(
                      hintText: 'Add address…',
                      border: OutlineInputBorder(),
                    ),
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
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    final t = _addrController.text.trim();
                    if (t.isNotEmpty) {
                      setState(() {
                        _addresses.add(t);
                        _addrController.clear();
                      });
                    }
                  },
                  child: const Text('Add'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _plan, 
                  child: _isLoading ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ) : const Text('Plan'),
                ),
              ],
            ),
          ),
          if (_addresses.isNotEmpty)
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _addresses.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => Chip(label: Text('${i + 1}. ${_addresses[i]}')),
              ),
            ),
          Expanded(
            child: FlutterMap(
              mapController: mapController,
              options: MapOptions(
                initialCenter: const LatLng(19.0760, 72.8777), // Mumbai default
                initialZoom: 11,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.delivery_route_frontend',
                ),
                PolylineLayer(polylines: [
                  Polyline(points: _polyline, color: Colors.blue, strokeWidth: 4),
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
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _ordered.length >= 2 ? _openExternalNav : null,
                      icon: const Icon(Icons.navigation),
                      label: const Text('Start Navigation (Google Maps)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void main() {
  runApp(const MaterialApp(home: MapScreen()));
}
