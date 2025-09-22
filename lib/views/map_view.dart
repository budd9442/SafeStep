import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class MapView extends StatefulWidget {
  final LatLng? currentPosition;
  final bool loading;
  final String? error;
  final LatLng? dangerZoneCenter;
  final double? dangerZoneRadius;
  final List<DangerZone>? dangerZones;
  final void Function(DangerZone)? onDangerZoneTap;
  const MapView({
    super.key,
    required this.currentPosition,
    required this.loading,
    required this.error,
    this.dangerZoneCenter,
    this.dangerZoneRadius,
    this.dangerZones,
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
  late LatLng _dangerZoneCenter;
  late double _dangerZoneRadiusMeters;
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
      // Network URL - download the image
      try {
        final response = await http.get(Uri.parse(profilePicPath));
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

  Future<String?> _fetchAndCacheProfilePic() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      // First try to get the profile picture URL from Firestore
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final profilePicUrl = userData?['profilePicUrl'] ?? userData?['profilePic'];
      
      if (profilePicUrl != null && profilePicUrl.isNotEmpty) {
        if (profilePicUrl.startsWith('http')) {
          // It's already a URL, return it directly
          return profilePicUrl;
        } else {
          // It's a Firebase Storage path, get the download URL
          final ref = FirebaseStorage.instanceFor(bucket: 'gs://safestep-d8237.firebasestorage.app').ref().child(profilePicUrl);
          return await ref.getDownloadURL();
        }
      }
      
      // Fallback to the old method
      final ref = FirebaseStorage.instanceFor(bucket: 'gs://safestep-d8237.firebasestorage.app').ref().child('profile_pics/${user.uid}.jpg');
      final url = await ref.getDownloadURL();
      return url;
    } catch (e) {
      return null;
    }
  }

  Future<void> _loadProfilePointerMarkerWithFallback() async {
    final profilePicPath = await _fetchAndCacheProfilePic();
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
    _dangerZoneCenter = widget.dangerZoneCenter ?? const LatLng(6.9754032, 79.9155534);
    _dangerZoneRadiusMeters = widget.dangerZoneRadius ?? 320.0;
    _loadProfilePointerMarkerWithFallback(); // Download and use pfp for marker immediately
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateDangerZones());
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the user changes (e.g. after login), reload the marker
    if (FirebaseAuth.instance.currentUser?.uid != null &&
        FirebaseAuth.instance.currentUser?.uid != oldWidget.currentPosition?.hashCode.toString()) {
      _loadProfilePointerMarkerWithFallback();
    }
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
    _markers = {
      if (widget.currentPosition != null && _profilePointerDescriptor != null)
        Marker(
          markerId: const MarkerId('user'),
          position: widget.currentPosition!,
          icon: _profilePointerDescriptor!,
          anchor: const Offset(0.5, 0.5),
        ),
    };
  }

  /// Call this to force refresh the profile pointer marker after pfp update
  Future<void> refreshProfilePointerMarker() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/profile_${user.uid}.jpg');
      if (await file.exists()) {
        await file.delete();
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
