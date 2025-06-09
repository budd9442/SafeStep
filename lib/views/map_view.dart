import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:vibration/vibration.dart';

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
  const DangerZone(this.center, this.radius);
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
  late List<DangerZone> _dangerZones;
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
    // Always include the initial danger zone if not already present
    final initialZone = DangerZone(_dangerZoneCenter, _dangerZoneRadiusMeters);
    if (widget.dangerZones != null && widget.dangerZones!.isNotEmpty) {
      // Only add initial if not present
      final alreadyIncluded = widget.dangerZones!.any((z) => z.center == initialZone.center && z.radius == initialZone.radius);
      _dangerZones = alreadyIncluded ? List.from(widget.dangerZones!) : [initialZone, ...widget.dangerZones!];
    } else {
      _dangerZones = [initialZone];
    }
    _lastMarkerPosition = widget.currentPosition;
    _animatedMarkerPosition = widget.currentPosition;
    _markerMoveController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _initializeNotifications();
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

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Always include the initial danger zone in the list
    final initialZone = DangerZone(_dangerZoneCenter, _dangerZoneRadiusMeters);
    if (widget.dangerZones != null && widget.dangerZones!.isNotEmpty) {
      final alreadyIncluded = widget.dangerZones!.any((z) => z.center == initialZone.center && z.radius == initialZone.radius);
      setState(() {
        _dangerZones = alreadyIncluded ? List.from(widget.dangerZones!) : [initialZone, ...widget.dangerZones!];
      });
    } else {
      setState(() {
        _dangerZones = [initialZone];
      });
    }
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

  @override
  Widget build(BuildContext context) {
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
                // Danger zone circles (multiple)
                ..._dangerZones.map((zone) => CircleLayer(
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
  }
}
