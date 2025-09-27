import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:safestep/services/local_session.dart';
import 'shared_user_location_history_screen.dart';

class MapView extends StatefulWidget {
  final LatLng? currentPosition;
  final bool loading;
  final String? error;
  final LatLng? dangerZoneCenter;
  final double? dangerZoneRadius;
  final List<DangerZone>? dangerZones;
  final Map<String, Map<String, dynamic>>? sharedLocations;
  final void Function(DangerZone)? onDangerZoneTap;
  const MapView({
    super.key,
    required this.currentPosition,
    required this.loading,
    required this.error,
    this.dangerZoneCenter,
    this.dangerZoneRadius,
    this.dangerZones,
    this.sharedLocations,
    this.onDangerZoneTap,
  });

  // Use this key to control MapViewState from outside
  static final GlobalKey<MapViewState> globalKey = GlobalKey<MapViewState>();

  @override
  State<MapView> createState() => MapViewState();
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

class MapViewState extends State<MapView> {
  GoogleMapController? _mapController;
  Set<Circle> _dangerZoneCircles = {};
  Set<Marker> _markers = {};
  bool _userMovedMap = false;
  BitmapDescriptor? _profilePointerDescriptor;

  Future<BitmapDescriptor> createProfilePointerMarker(String profilePicPath) async {
    // Load the base pointer image (always from assets)
    final pointerBytes = (await rootBundle.load('assets/pointer.png')).buffer.asUint8List();
    final pointerCodec = await ui.instantiateImageCodec(pointerBytes, targetWidth: 160, targetHeight: 200);
    final pointerFrame = await pointerCodec.getNextFrame();
    final pointerImage = pointerFrame.image;

    // Load the profile image (from URL, file, or asset)
    Uint8List profileBytes;
    if (profilePicPath.startsWith('http')) {
      // Network URL - download the image with cache-busting
      try {
        // Add cache-busting parameter to prevent caching
        final cacheBustedUrl = '$profilePicPath?t=${DateTime.now().millisecondsSinceEpoch}';
        final response = await http.get(Uri.parse(cacheBustedUrl));
        if (response.statusCode == 200) {
          profileBytes = response.bodyBytes;
        } else {
          throw Exception('Failed to load image from URL');
        }
      } catch (e) {
        // Fallback to default icon
        return await _createPointerWithIconMarker();
      }
    } else if (profilePicPath.startsWith('/') || profilePicPath.startsWith('file://')) {
      // Local file
      profileBytes = await File(profilePicPath).readAsBytes();
    } else {
      // Asset
      profileBytes = (await rootBundle.load(profilePicPath)).buffer.asUint8List();
    }
    
    final profileCodec = await ui.instantiateImageCodec(profileBytes, targetWidth: 150, targetHeight: 150);
    final profileFrame = await profileCodec.getNextFrame();
    final profileImage = profileFrame.image;

    // Compose the images
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    // Draw pointer
    canvas.drawImage(pointerImage, Offset.zero, paint);
    // Draw profile image in the center circle, moved down and right
    final center = Offset(80, 75); // Moved down and right
    final radius = 60.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    // Draw solid light purple background for the profile circle
    final bgPaint = Paint()..color = const Color(0xFFEDE6FF);
    canvas.drawCircle(center, radius, bgPaint);
    canvas.saveLayer(rect, Paint());
    canvas.clipPath(Path()..addOval(rect));
    canvas.drawImage(profileImage, Offset(center.dx - radius, center.dy - radius), paint);
    canvas.restore();
    final composed = await recorder.endRecording().toImage(200, 200);
    final pngBytes = await composed.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(pngBytes!.buffer.asUint8List());
  }

  Future<void> loadProfilePointerMarker(String profilePicPath) async {
    // Always reload the marker, even if the path is the same (to handle file overwrite)
    final marker = await createProfilePointerMarker(profilePicPath);
    setState(() {
      _profilePointerDescriptor = marker;
      _updateDangerZones();
    });
  }

  Future<String?> _fetchProfilePicWithoutCache() async {
    try {
      // Use local session user ID
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null || localUserId.isEmpty) return null;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(localUserId).get();
      final userData = userDoc.data();
      final profilePicUrl = (userData?['profilePicUrl'] ?? userData?['profilePic']) as String?;

      if (profilePicUrl != null && profilePicUrl.isNotEmpty) {
        if (profilePicUrl.startsWith('http')) {
          // It's already a URL, return it with cache-busting to prevent caching
          return '$profilePicUrl?t=${DateTime.now().millisecondsSinceEpoch}';
        } else {
          // It's a Firebase Storage path, get the download URL with cache-busting
          final ref = FirebaseStorage.instanceFor(bucket: 'gs://safestep-d8237.firebasestorage.app').ref().child(profilePicUrl);
          final url = await ref.getDownloadURL();
          return '$url?t=${DateTime.now().millisecondsSinceEpoch}';
        }
      }

      // Fallback to Firebase Storage with user ID - no caching
      final ref = FirebaseStorage.instanceFor(bucket: 'gs://safestep-d8237.firebasestorage.app').ref().child('profile_pics/$localUserId.jpg');
      final url = await ref.getDownloadURL();
      return '$url?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      print('Error fetching profile pic: $e');
      return null;
    }
  }

  Future<void> _loadProfilePointerMarkerWithFallback() async {
    final profilePicPath = await _fetchProfilePicWithoutCache();
    if (profilePicPath != null) {
      final marker = await createProfilePointerMarker(profilePicPath);
      setState(() {
        _profilePointerDescriptor = marker;
        _updateDangerZones();
      });
    } else {
      // Use fallback: draw pointer with icon
      final marker = await _createPointerWithIconMarker();
      setState(() {
        _profilePointerDescriptor = marker;
        _updateDangerZones();
      });
    }
  }

  Future<BitmapDescriptor> _createPointerWithIconMarker() async {
    final pointerBytes = (await rootBundle.load('assets/pointer.png')).buffer.asUint8List();
    final pointerCodec = await ui.instantiateImageCodec(pointerBytes, targetWidth: 128, targetHeight: 128);
    final pointerFrame = await pointerCodec.getNextFrame();
    final pointerImage = pointerFrame.image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    // Draw pointer
    canvas.drawImage(pointerImage, Offset.zero, paint);
    // Draw fallback icon (e.g. person) in the center
    final icon = Icons.person;
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 64, fontFamily: 'MaterialIcons'))
      ..addText(String.fromCharCode(icon.codePoint));
    final para = builder.build();
    para.layout(const ui.ParagraphConstraints(width: 72));
    canvas.drawParagraph(para, const Offset(64 - 36, 54 - 36));
    final composed = await recorder.endRecording().toImage(128, 128);
    final pngBytes = await composed.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(pngBytes!.buffer.asUint8List());
  }

  @override
  void initState() {
    super.initState();
    _loadProfilePointerMarkerWithFallback(); // Download and use pfp for marker immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateDangerZones());
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the user changes (e.g. after login), reload the marker
    _loadProfilePointerMarkerWithFallback();
    setState(() {
      _updateDangerZones();
    });
  }

  void _updateDangerZones() {
    final zones = widget.dangerZones ?? [];
    _dangerZoneCircles = zones.map((zone) => Circle(
      circleId: CircleId(zone.id ?? zone.center.toString()),
      center: zone.center,
      radius: zone.radius,
      fillColor: const Color(0x44E0006A),
      strokeColor: Colors.transparent,
      strokeWidth: 0,
      consumeTapEvents: true,
      onTap: () {
        if (widget.onDangerZoneTap != null) {
          widget.onDangerZoneTap!(zone);
        }
      },
    )).toSet();
    
    // Create markers set
    _markers = <Marker>{};
    
    // Add user's own marker
    if (widget.currentPosition != null && _profilePointerDescriptor != null) {
      _markers.add(
        Marker(
          markerId: const MarkerId('user'),
          position: widget.currentPosition!,
          icon: _profilePointerDescriptor!,
          anchor: const Offset(0.5, 0.5),
        ),
      );
    }
    
    // Add shared location markers - update asynchronously
    _updateSharedLocationMarkers();
  }

  Future<void> _updateSharedLocationMarkers() async {
    print('🔄 [SHARED MARKERS] Updating shared location markers...');
    if (widget.sharedLocations == null) {
      print('⚠️ [SHARED MARKERS] No shared locations data');
      return;
    }
    
    print('📊 [SHARED MARKERS] Found ${widget.sharedLocations!.length} shared locations');
    final sharedMarkers = <Marker>{};
    
    for (final entry in widget.sharedLocations!.entries) {
      final userId = entry.key;
      final locationData = entry.value;
      final lat = locationData['latitude'] as double?;
      final lng = locationData['longitude'] as double?;
      final name = locationData['name'] as String? ?? 'Unknown';
      
      if (lat != null && lng != null) {
        final customIcon = await _createSharedLocationMarker(name, locationData['profileImageUrl']);
        sharedMarkers.add(
          Marker(
            markerId: MarkerId('shared_$userId'),
            position: LatLng(lat, lng),
            icon: customIcon,
            anchor: const Offset(0.5, 0.5),
            infoWindow: InfoWindow(
              title: name,
              snippet: 'Tap to view location history',
            ),
            onTap: () => _onSharedLocationMarkerTap(userId, name, locationData['profileImageUrl']),
          ),
        );
        print('📍 [SHARED MARKER] Created marker for $name ($userId) at $lat, $lng');
      }
    }
    
    // Update markers with shared location markers
    setState(() {
      _markers = _markers.where((marker) => !marker.markerId.value.startsWith('shared_')).toSet();
      _markers.addAll(sharedMarkers);
    });
  }

  Future<BitmapDescriptor> _createSharedLocationMarker(String name, String? profileImageUrl) async {
    // Load the base pointer image (same as user's pin)
    final pointerBytes = (await rootBundle.load('assets/pointer.png')).buffer.asUint8List();
    final pointerCodec = await ui.instantiateImageCodec(pointerBytes, targetWidth: 160, targetHeight: 200);
    final pointerFrame = await pointerCodec.getNextFrame();
    final pointerImage = pointerFrame.image;

    // Create a colored version of the pointer for shared locations
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    
    // Apply a color filter to make the pointer blue/teal instead of purple
    final colorFilter = const ColorFilter.matrix([
      0.0, 0.0, 1.0, 0.0, 0.0,  // Red channel -> Blue
      0.0, 0.8, 0.0, 0.0, 0.0,  // Green channel -> Teal
      1.0, 0.0, 0.0, 0.0, 0.0,  // Blue channel -> Red (for contrast)
      0.0, 0.0, 0.0, 1.0, 0.0,  // Alpha channel unchanged
    ]);
    
    // Draw the colored pointer with color filter
    paint.colorFilter = colorFilter;
    canvas.drawImage(pointerImage, Offset.zero, paint);
    
    // Load profile image if available, otherwise use fallback
    Uint8List? profileBytes;
    ui.Image? profileImage;
    
    if (profileImageUrl != null && profileImageUrl.isNotEmpty && profileImageUrl.startsWith('http')) {
      try {
        // Add cache-busting parameter to prevent caching
        final cacheBustedUrl = '$profileImageUrl?t=${DateTime.now().millisecondsSinceEpoch}';
        final response = await http.get(Uri.parse(cacheBustedUrl));
        if (response.statusCode == 200) {
          profileBytes = response.bodyBytes;
          final profileCodec = await ui.instantiateImageCodec(profileBytes, targetWidth: 150, targetHeight: 150);
          final profileFrame = await profileCodec.getNextFrame();
          profileImage = profileFrame.image;
        }
      } catch (e) {
        print('⚠️ [SHARED MARKER] Failed to load profile image: $e');
      }
    }
    
    if (profileImage != null) {
      // Draw profile image in the center of the pointer
      final profilePaint = Paint();
      canvas.drawImage(profileImage, const Offset(5, 5), profilePaint);
    } else {
      // Draw fallback icon (person) in the center
      final icon = Icons.person;
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 64, fontFamily: 'MaterialIcons'))
        ..addText(String.fromCharCode(icon.codePoint));
      final para = builder.build();
      para.layout(const ui.ParagraphConstraints(width: 72));
      canvas.drawParagraph(para, const Offset(64 - 36, 54 - 36));
    }
    
    final composed = await recorder.endRecording().toImage(160, 200);
    final pngBytes = await composed.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(pngBytes!.buffer.asUint8List());
  }

  void _onSharedLocationMarkerTap(String userId, String userName, String? profileImageUrl) {
    // Find the current location from shared locations
    if (widget.sharedLocations != null && widget.sharedLocations!.containsKey(userId)) {
      final locationData = widget.sharedLocations![userId];
      final lat = locationData?['latitude'] as double?;
      final lng = locationData?['longitude'] as double?;
      
      if (lat != null && lng != null) {
        print('🎯 [MARKER TAP] Opening location history for $userName ($userId)');
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SharedUserLocationHistoryScreen(
              userId: userId,
              userName: userName,
              profileImageUrl: profileImageUrl,
              currentLocation: LatLng(lat, lng),
            ),
          ),
        );
      } else {
        print('⚠️ [MARKER TAP] Invalid location data for $userId');
      }
    } else {
      print('⚠️ [MARKER TAP] User $userId not found in shared locations');
    }
  }

  /// Call this to force refresh the profile pointer marker after pfp update
  Future<void> refreshProfilePointerMarker() async {
    try {
      final dir = await getTemporaryDirectory();
      // Find the authenticated user to get the user ID
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('isAuthenticated', isEqualTo: true)
          .limit(1)
          .get();

      if (usersQuery.docs.isNotEmpty) {
        final userDoc = usersQuery.docs.first;
        final file = File('${dir.path}/profile_${userDoc.id}.jpg');
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}
    await _loadProfilePointerMarkerWithFallback();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.currentPosition ?? const LatLng(6.9754032, 79.9155534),
              zoom: 16,
            ),
            circles: _dangerZoneCircles,
            markers: _markers,
            myLocationEnabled: false, // Disable blue dot
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onCameraMove: (position) {
              if (!_userMovedMap) {
                setState(() {
                  _userMovedMap = true;
                });
              }
            },
          ),
          if (_userMovedMap)
            Positioned(
              right: 18,
              bottom: 90,
              child: FloatingActionButton(
                mini: true,
                backgroundColor: Colors.white,
                elevation: 3,
                onPressed: () {
                  if (widget.currentPosition != null && _mapController != null) {
                    _mapController!.animateCamera(CameraUpdate.newLatLng(widget.currentPosition!));
                    setState(() {
                      _userMovedMap = false;
                    });
                  }
                },
                child: const Icon(Icons.my_location, color: Color(0xFF8F5FE8)),
              ),
            ),
        ],
      ),
    );
  }
}
