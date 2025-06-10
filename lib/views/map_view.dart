import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MapView extends StatefulWidget {
  final LatLng? currentPosition;
  final bool loading;
  final String? error;
  final LatLng? dangerZoneCenter;
  final double? dangerZoneRadius;
  final List<DangerZone>? dangerZones; // NEW: list of zones
  const MapView({
    super.key,
    required this.currentPosition,
    required this.loading,
    required this.error,
    this.dangerZoneCenter,
    this.dangerZoneRadius,
    this.dangerZones,
  });
  @override
  State<MapView> createState() => _MapViewState();
}

class DangerZone {
  final LatLng center;
  final double radius;
  final String? id;
  final String? description;
  DangerZone(this.center, this.radius, {this.id, this.description});

  factory DangerZone.fromFirestore(Map<String, dynamic> data, {String? id}) {
    return DangerZone(
      LatLng((data['lat'] ?? 0.0) * 1.0, (data['lng'] ?? 0.0) * 1.0),
      (data['radius'] ?? 0.0) * 1.0,
      id: id,
      description: data['description'] as String?,
    );
  }
}

class _MapViewState extends State<MapView> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  bool _userMovedMap = false;
  bool _programmaticMove = false; // Track if move is programmatic
  String get _tileUrl {
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  // Danger zone state
  late LatLng _dangerZoneCenter;
  late double _dangerZoneRadiusMeters;
  bool _alertSent = false;

  LatLng? _lastMarkerPosition;
  AnimationController? _markerMoveController;
  Animation<double>? _markerMoveAnimation;
  LatLng? _animatedMarkerPosition;

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  bool _isInDangerZone(LatLng? pos) {
    if (pos == null) return false;
    final Distance distance = const Distance();
    return distance(pos, _dangerZoneCenter) <= _dangerZoneRadiusMeters;
  }

  void _centerOnUser() {
    if (widget.currentPosition != null) {
      _programmaticMove = true;
      _mapController.move(widget.currentPosition!, 16); // Hardcoded zoom 16
      setState(() {
        _userMovedMap = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _dangerZoneCenter = widget.dangerZoneCenter ?? const LatLng(6.9754032, 79.9155534);
    _dangerZoneRadiusMeters = widget.dangerZoneRadius ?? 320.0;
    _lastMarkerPosition = widget.currentPosition;
    _animatedMarkerPosition = widget.currentPosition;
    _markerMoveController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _initializeNotifications();

    _dangerZonesStream = FirebaseFirestore.instance
        .collection('dangerzones')
        .orderBy('reportedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => DangerZone.fromFirestore(doc.data(), id: doc.id)).toList());
  }

  Future<void> _initializeNotifications() async {
    const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
    final InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
    await _notificationsPlugin.initialize(initializationSettings);
  }

  Future<void> _sendDangerZoneNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
      'danger_zone_channel',
      'Danger Zone Alerts',
      channelDescription: 'Notification channel for danger zone alerts',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
    );
    const NotificationDetails platformChannelSpecifics = NotificationDetails(android: androidPlatformChannelSpecifics);
    await _notificationsPlugin.show(
      0,
      'Danger Zone Alert',
      'You have entered a danger zone!',
      platformChannelSpecifics,
    );
  }

  Future<void> _vibrateDangerZone() async {
    if (await Vibration.hasVibrator()) {
      for (int i = 0; i < 5; i++) {
        Vibration.vibrate(duration: 200);
        await Future.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  @override
  void dispose() {
    _markerMoveController?.dispose();
    super.dispose();
  }

  void _animateMarkerMove(LatLng from, LatLng to) {
    _markerMoveController!.reset();
    _markerMoveAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _markerMoveController!, curve: Curves.easeInOut));
    final double latDelta = to.latitude - from.latitude;
    final double lngDelta = to.longitude - from.longitude;
    void markerListener() {
      final t = _markerMoveAnimation!.value;
      setState(() {
        _animatedMarkerPosition = LatLng(from.latitude + latDelta * t, from.longitude + lngDelta * t);
      });
    }
    _markerMoveController!.addListener(markerListener);
    _markerMoveController!.forward(from: 0).whenComplete(() {
      _markerMoveController!.removeListener(markerListener);
      _lastMarkerPosition = to;
      setState(() {
        _animatedMarkerPosition = to;
      });
    });
  }

  void updateDangerZone(LatLng center, double radius) {
    setState(() {
      _dangerZoneCenter = center;
      _dangerZoneRadiusMeters = radius;
    });
  }

  late Stream<List<DangerZone>> _dangerZonesStream;

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Animate marker if position changed
    if (widget.currentPosition != null && widget.currentPosition != _lastMarkerPosition) {
      if (_lastMarkerPosition != null) {
        _animateMarkerMove(_lastMarkerPosition!, widget.currentPosition!);
      } else {
        setState(() {
          _animatedMarkerPosition = widget.currentPosition;
        });
      }
      _lastMarkerPosition = widget.currentPosition;
    }
    // Center and follow marker if user hasn't moved map
    if (!_userMovedMap && _animatedMarkerPosition != null) {
      _programmaticMove = true;
      // Use current zoom instead of hardcoded 18
      final currentZoom = _mapController.camera.zoom;
      _mapController.move(_animatedMarkerPosition!, currentZoom);
      _lastMarkerPosition = _animatedMarkerPosition;
    }
    // Always update the marker when the location changes
    if (oldWidget.currentPosition != widget.currentPosition) {
      if (mounted) setState(() {});
    }
    if (!_alertSent && _isInDangerZone(widget.currentPosition)) {
      _alertSent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alert: You have entered a danger zone!'), backgroundColor: Colors.red),
        );
        _sendDangerZoneNotification();
        _vibrateDangerZone();
      });
    }
    if (_alertSent && !_isInDangerZone(widget.currentPosition)) {
      _alertSent = false;
    }
  }

  int? _selectedZoneIndex;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DangerZone>>(
      stream: _dangerZonesStream,
      builder: (context, snapshot) {
        List<DangerZone> zones = snapshot.data ?? [];
        // Always include the initial danger zone if not present
        final initialZone = DangerZone(_dangerZoneCenter, _dangerZoneRadiusMeters);
        if (!zones.any((z) => z.center == initialZone.center && z.radius == initialZone.radius)) {
          zones = [initialZone, ...zones];
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: widget.currentPosition ?? LatLng(23.8151, 90.4250),
                    initialZoom: 16,
                    onMapEvent: (event) {
                      // Detach follow mode if the user moves the map (robust: any move not programmatic)
                      if ((event is MapEventMove || event is MapEventMoveEnd)) {
                        if (_programmaticMove) {
                          // Reset flag after programmatic move
                          _programmaticMove = false;
                        } else if (!_userMovedMap) {
                          setState(() {
                            _userMovedMap = true;
                          });
                        }
                      }
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrl,
                      additionalOptions: <String, String>{},
                      userAgentPackageName: 'com.example.safestep',
                      tileProvider: NetworkTileProvider(),
                    ),
                    // Danger zone circles (multiple, from Firestore)
                    ...zones.map((zone) => CircleLayer(
                      circles: [
                        CircleMarker(
                          point: zone.center,
                          color: const Color(0x44E0006A),
                          borderStrokeWidth: 0,
                          useRadiusInMeter: true,
                          radius: zone.radius,
                        ),
                      ],
                    )),
                    // Add a transparent GestureDetector overlay for interactivity
                    if (zones.isNotEmpty)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTapDown: (details) {
                            final tapPoint = details.localPosition;
                            final map = _mapController.camera;
                            final size = (context.findRenderObject() as RenderBox).size;
                            final x = tapPoint.dx / size.width;
                            final y = tapPoint.dy / size.height;
                            final bounds = map.visibleBounds;
                            final lat = bounds.north + (bounds.south - bounds.north) * y;
                            final lng = bounds.west + (bounds.east - bounds.west) * x;
                            final tapped = LatLng(lat, lng);
                            final Distance distance = const Distance();
                            // Replace the AlertDialog in the GestureDetector with a custom, modern bottom sheet for danger zone info
                            for (int i = 0; i < zones.length; i++) {
                              final zone = zones[i];
                              if (distance(zone.center, tapped) <= zone.radius) {
                                showModalBottomSheet(
                                  context: context,
                                  shape: const RoundedRectangleBorder(
                                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                                  ),
                                  builder: (_) => Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFE0006A), size: 32),
                                            const SizedBox(width: 12),
                                            Text(
                                              'Danger Zone',
                                              style: TextStyle(
                                                fontSize: 22,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFFE0006A),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 16),
                                        Text(
                                          zone.description ?? 'No description',
                                          style: const TextStyle(fontSize: 16, color: Color(0xFF232946)),
                                        ),
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            const Icon(Icons.circle, size: 16, color: Color(0xFFE0006A)),
                                            const SizedBox(width: 6),
                                            Text('Radius: ${zone.radius.toStringAsFixed(0)} m', style: const TextStyle(fontSize: 15)),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            const Icon(Icons.location_on, size: 16, color: Color(0xFF8F5FE8)),
                                            const SizedBox(width: 6),
                                            Text('Lat: ${zone.center.latitude.toStringAsFixed(5)}'),
                                            const SizedBox(width: 12),
                                            Text('Lng: ${zone.center.longitude.toStringAsFixed(5)}'),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton(
                                            onPressed: () => Navigator.pop(context),
                                            child: const Text('Close', style: TextStyle(color: Color(0xFFE0006A), fontWeight: FontWeight.bold)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                                break;
                              }
                            }
                          },
                        ),
                      ),
                    if (_animatedMarkerPosition != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            width: 60.0,
                            height: 60.0,
                            point: _animatedMarkerPosition!,
                            child: const Icon(Icons.location_on, color: Color(0xFF8F5FE8), size: 44),
                          ),
                        ],
                      ),
                    // Demo marker for Yonarli
                    MarkerLayer(
                      markers: [
                        Marker(
                          width: 60.0,
                          height: 60.0,
                          point: LatLng(23.8151, 90.4250),
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF232946),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(Icons.location_pin, color: Colors.white, size: 38),
                          ),
                        ),
                      ],
                    ),
                    ...zones.asMap().entries.map((entry) {
                      final i = entry.key;
                      final zone = entry.value;
                      if (_selectedZoneIndex == i) {
                        return AnimatedPositioned(
                          duration: const Duration(milliseconds: 300),
                          left: null, // Will be positioned by marker
                          top: null,
                          child: Center(
                            child: Material(
                              color: Colors.transparent,
                              child: AnimatedOpacity(
                                opacity: 1.0,
                                duration: const Duration(milliseconds: 300),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                  margin: const EdgeInsets.only(bottom: 60),
                                  decoration: BoxDecoration(
                                    color: Colors.pink.shade50,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.08),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    zone.description ?? 'No description',
                                    style: const TextStyle(color: Color(0xFFE0006A), fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      } else {
                        return const SizedBox.shrink();
                      }
                    }).toList(),
                  ],
                ),
                if (_userMovedMap)
                  Positioned(
                    right: 18,
                    bottom: 90, // Above nav/chat bar
                    child: FloatingActionButton(
                      mini: true,
                      backgroundColor: Colors.white,
                      elevation: 3,
                      onPressed: _centerOnUser,
                      child: const Icon(Icons.my_location, color: Color(0xFF8F5FE8)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
