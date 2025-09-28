import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:safestep/services/local_session.dart';
import 'shared_user_location_history_screen.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';

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
  
  // Profile image cache
  static final Map<String, ui.Image> _profileImageCache = {};
  static final Map<String, DateTime> _cacheTimestamps = {};
  
  // Marker cache to prevent unnecessary recreation
  final Map<String, BitmapDescriptor> _markerCache = {};
  Map<String, Map<String, dynamic>>? _lastSharedLocations;

  Future<BitmapDescriptor> createProfilePointerMarker(String profilePicPath) async {
    // Load the base pointer image (always from assets) - larger size
    final pointerBytes = (await rootBundle.load('assets/pointer.png')).buffer.asUint8List();
    final pointerCodec = await ui.instantiateImageCodec(pointerBytes, targetWidth: 120, targetHeight: 150);
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
    
    final profileCodec = await ui.instantiateImageCodec(profileBytes, targetWidth: 112, targetHeight: 112);
    final profileFrame = await profileCodec.getNextFrame();
    final profileImage = profileFrame.image;

    // Compose the images
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint();
    // Draw pointer
    canvas.drawImage(pointerImage, Offset.zero, paint);
    // Draw circular profile image in the center of the pointer
    final center = Offset(60, 50); // Moved higher in the pointer
    final radius = 40.0; // Radius for the circular crop
    
    // Create circular clipping path
    final clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.save();
    canvas.clipPath(clipPath);
    
    // Draw the profile image scaled to fit the circle
    final srcRect = Rect.fromLTWH(0, 0, profileImage.width.toDouble(), profileImage.height.toDouble());
    final dstRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawImageRect(profileImage, srcRect, dstRect, paint);
    
    canvas.restore();
    final composed = await recorder.endRecording().toImage(120, 150);
    final pngBytes = await composed.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(pngBytes!.buffer.asUint8List());
  }

  Future<void> loadProfilePointerMarker(String profilePicPath) async {
    // Always reload the marker, even if the path is the same (to handle file overwrite)
    final marker = await createProfilePointerMarker(profilePicPath);
    if (mounted) {
    setState(() {
      _profilePointerDescriptor = marker;
      _updateDangerZones();
    });
    }
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
          // It's a Firebase Storage path, but we don't use Storage anymore
          return null;
        }
      }

      // No fallback to Firebase Storage - use URL only
      return null;
    } catch (e) {
      print('Error fetching profile pic: $e');
      return null;
    }
  }

  Future<void> _loadProfilePointerMarkerWithFallback() async {
    final profilePicPath = await _fetchProfilePicWithoutCache();
    if (profilePicPath != null) {
      final marker = await createProfilePointerMarker(profilePicPath);
      if (mounted) {
      setState(() {
        _profilePointerDescriptor = marker;
        _updateDangerZones();
      });
      }
    } else {
      // Use fallback: draw pointer with icon
      final marker = await _createPointerWithIconMarker();
      if (mounted) {
      setState(() {
        _profilePointerDescriptor = marker;
        _updateDangerZones();
      });
      }
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
    _markers = <Marker>{}; // Initialize markers set
    _loadProfilePointerMarkerWithFallback(); // Download and use pfp for marker immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateDangerZones();
      _updateSharedLocationMarkers(); // Add shared location markers on init
    });
  }

  @override
  void didUpdateWidget(covariant MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the user changes (e.g. after login), reload the marker
    _loadProfilePointerMarkerWithFallback();
    
    // Only update shared location markers if the data actually changed
    if (oldWidget.sharedLocations != widget.sharedLocations) {
      _updateSharedLocationMarkers();
    }
    
    if (mounted) {
    setState(() {
      _updateDangerZones();
    });
    }
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
    
    _updateUserMarker();
  }

  void _updateUserMarker() {
    // Remove existing user marker
    _markers.removeWhere((marker) => marker.markerId.value == 'user');
    
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
  }

  Future<void> _updateSharedLocationMarkers() async {
    print('🔄 [SHARED MARKERS] Updating shared location markers...');
    if (widget.sharedLocations == null) {
      print('⚠️ [SHARED MARKERS] No shared locations data');
      return;
    }
    
    // Check if shared locations data has actually changed
    if (_lastSharedLocations != null && _areSharedLocationsEqual(_lastSharedLocations!, widget.sharedLocations!)) {
      print('✅ [SHARED MARKERS] No changes detected, skipping marker update');
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
      final profileImageUrl = locationData['profileImageUrl'] as String?;
      
      print('🔄 [SHARED MARKERS] Processing user $userId: name=$name, profileUrl=$profileImageUrl');
      
      if (lat != null && lng != null) {
        // Check if we already have a cached marker for this user
        BitmapDescriptor? customIcon = _markerCache[userId];
        
        if (customIcon == null) {
          // Create new marker and cache it
          customIcon = await _createSharedLocationMarker(name, profileImageUrl);
          _markerCache[userId] = customIcon;
          print('🆕 [SHARED MARKER] Created and cached new marker for $name ($userId)');
        } else {
          print('♻️ [SHARED MARKER] Using cached marker for $name ($userId)');
        }
        
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
            onTap: () => _onSharedLocationMarkerTap(userId, name, profileImageUrl),
          ),
        );
        print('📍 [SHARED MARKER] Added marker for $name ($userId) at $lat, $lng');
      }
    }
    
    // Update markers with shared location markers
    if (mounted) {
      setState(() {
        _markers = _markers.where((marker) => !marker.markerId.value.startsWith('shared_')).toSet();
        _markers.addAll(sharedMarkers);
      });
    }
    
    // Store current shared locations for comparison
    _lastSharedLocations = Map.from(widget.sharedLocations!);
  }

  Future<BitmapDescriptor> _createSharedLocationMarker(String name, String? profileImageUrl) async {
    // Load the base pointer image (same as user's pin) - larger size
    final pointerBytes = (await rootBundle.load('assets/pointer.png')).buffer.asUint8List();
    final pointerCodec = await ui.instantiateImageCodec(pointerBytes, targetWidth: 120, targetHeight: 150);
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
    
    // Load profile image with caching
    ui.Image? profileImage = await _loadCachedProfileImage(profileImageUrl);
    
    if (profileImage != null) {
      // Draw circular profile image in the center of the pointer
      final profilePaint = Paint();
      final center = const Offset(60, 53); // Moved higher in the pointer
      final radius = 40.0; // Radius for the circular crop
      
      // Create circular clipping pathrR
      final clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
      canvas.save();
      canvas.clipPath(clipPath);
      
      // Draw the profile image scaled to fit the circle
      final srcRect = Rect.fromLTWH(0, 0, profileImage.width.toDouble(), profileImage.height.toDouble());
      final dstRect = Rect.fromCircle(center: center, radius: radius);
      canvas.drawImageRect(profileImage, srcRect, dstRect, profilePaint);
      
      canvas.restore();
    } else {
      // Draw fallback icon (person) in the center
      final icon = Icons.person;
      final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 48, fontFamily: 'MaterialIcons'))
        ..addText(String.fromCharCode(icon.codePoint));
      final para = builder.build();
      para.layout(const ui.ParagraphConstraints(width: 54));
      canvas.drawParagraph(para, const Offset(33, 51));
    }
    
    final composed = await recorder.endRecording().toImage(120, 150);
    final pngBytes = await composed.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(pngBytes!.buffer.asUint8List());
  }

  Future<ui.Image?> _loadCachedProfileImage(String? profileImageUrl) async {
    if (profileImageUrl == null || profileImageUrl.isEmpty || !profileImageUrl.startsWith('http')) {
      print('⚠️ [CACHE] No valid profile image URL: $profileImageUrl');
      return null;
    }

    // Create cache key from URL
    final cacheKey = _generateCacheKey(profileImageUrl);
    final now = DateTime.now();
    
    // Check if image is in cache and not expired (24 hours)
    if (_profileImageCache.containsKey(cacheKey) && _cacheTimestamps.containsKey(cacheKey)) {
      final cacheTime = _cacheTimestamps[cacheKey]!;
      if (now.difference(cacheTime).inHours < 24) {
        print('✅ [CACHE] Using cached profile image for: $profileImageUrl');
        return _profileImageCache[cacheKey];
      } else {
        // Remove expired cache entry
        _profileImageCache.remove(cacheKey);
        _cacheTimestamps.remove(cacheKey);
        print('🗑️ [CACHE] Removed expired cache entry for: $profileImageUrl');
      }
    }

    // Load image from network
    try {
      print('🔄 [CACHE] Loading profile image from network: $profileImageUrl');
      final response = await http.get(Uri.parse(profileImageUrl));
      
      if (response.statusCode == 200) {
        final profileBytes = response.bodyBytes;
        final profileCodec = await ui.instantiateImageCodec(profileBytes, targetWidth: 112, targetHeight: 112);
        final profileFrame = await profileCodec.getNextFrame();
        final profileImage = profileFrame.image;
        
        // Cache the image
        _profileImageCache[cacheKey] = profileImage;
        _cacheTimestamps[cacheKey] = now;
        
        print('✅ [CACHE] Successfully loaded and cached profile image');
        return profileImage;
      } else {
        print('❌ [CACHE] Failed to load profile image: HTTP ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ [CACHE] Failed to load profile image: $e');
      return null;
    }
  }

  String _generateCacheKey(String url) {
    // Remove query parameters and create a hash for the cache key
    final uri = Uri.parse(url);
    final cleanUrl = '${uri.scheme}://${uri.host}${uri.path}';
    final bytes = utf8.encode(cleanUrl);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static void clearProfileImageCache() {
    _profileImageCache.clear();
    _cacheTimestamps.clear();
    print('🗑️ [CACHE] Cleared all profile image cache');
  }

  bool _areSharedLocationsEqual(Map<String, Map<String, dynamic>> old, Map<String, Map<String, dynamic>> new_) {
    if (old.length != new_.length) return false;
    
    for (final entry in old.entries) {
      final userId = entry.key;
      final oldData = entry.value;
      final newData = new_[userId];
      
      if (newData == null) return false;
      
      // Compare key fields that would affect marker appearance
      if (oldData['name'] != newData['name'] ||
          oldData['profileImageUrl'] != newData['profileImageUrl']) {
        return false;
      }
    }
    
    return true;
  }

  Widget _buildCachedProfileImageWidget(String? profileImageUrl, double size) {
    if (profileImageUrl == null || profileImageUrl.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: const Color(0xFF8F5FE8).withOpacity(0.1),
        child: Icon(
          Icons.person,
          color: const Color(0xFF8F5FE8),
          size: size * 0.6,
        ),
      );
    }

    return FutureBuilder<ui.Image?>(
      future: _loadCachedProfileImage(profileImageUrl),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: size,
            height: size,
            color: const Color(0xFF8F5FE8).withOpacity(0.1),
            child: Center(
              child: SizedBox(
                width: size * 0.4,
                height: size * 0.4,
                child: const CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8F5FE8)),
                ),
              ),
            ),
          );
        }

        if (snapshot.hasError || snapshot.data == null) {
          return Container(
            width: size,
            height: size,
            color: const Color(0xFF8F5FE8).withOpacity(0.1),
            child: Icon(
              Icons.person,
              color: const Color(0xFF8F5FE8),
              size: size * 0.6,
            ),
          );
        }

        return Container(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _CircularImagePainter(snapshot.data!, size),
          ),
        );
      },
    );
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
            mapType: MapType.normal,
            // Reduce map detail to only show safe places
            buildingsEnabled: false,
            trafficEnabled: false,
            indoorViewEnabled: false,
            // Custom map style to hide road names and labels
            style: '''
              [
                {
                  "featureType": "all",
                  "elementType": "labels",
                  "stylers": [
                    {
                      "visibility": "off"
                    }
                  ]
                },
                {
                  "featureType": "poi",
                  "elementType": "labels",
                  "stylers": [
                    {
                      "visibility": "on"
                    }
                  ]
                },
                {
                  "featureType": "poi.business",
                  "elementType": "labels",
                  "stylers": [
                    {
                      "visibility": "on"
                    }
                  ]
                },
                {
                  "featureType": "poi.medical",
                  "elementType": "labels",
                  "stylers": [
                    {
                      "visibility": "on"
                    }
                  ]
                },
                {
                  "featureType": "poi.police",
                  "elementType": "labels",
                  "stylers": [
                    {
                      "visibility": "on"
                    }
                  ]
                },
                {
                  "featureType": "poi.school",
                  "elementType": "labels",
                  "stylers": [
                    {
                      "visibility": "on"
                    }
                  ]
                },
                {
                  "featureType": "poi.place_of_worship",
                  "elementType": "labels",
                  "stylers": [
                    {
                      "visibility": "on"
                    }
                  ]
                },
                {
                  "featureType": "transit.station",
                  "elementType": "labels",
                  "stylers": [
                    {
                      "visibility": "on"
                    }
                  ]
                }
              ]
            ''',
            onMapCreated: (controller) {
              _mapController = controller;
            },
            onCameraMove: (position) {
              if (!_userMovedMap && mounted) {
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
                    if (mounted) {
                    setState(() {
                      _userMovedMap = false;
                    });
                    }
                  }
                },
                child: const Icon(Icons.my_location, color: Color(0xFF8F5FE8)),
              ),
            ),
          // Profile pictures for shared location users
          if (widget.sharedLocations != null && widget.sharedLocations!.isNotEmpty)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF8F5FE8).withOpacity(0.1),
                        ),
                        child: const Icon(
                          Icons.location_on,
                          color: Color(0xFF8F5FE8),
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ...widget.sharedLocations!.entries.map((entry) {
                        final locationData = entry.value;
                        final profileImageUrl = locationData['profileImageUrl'] as String?;
                        final lat = locationData['latitude'] as double?;
                        final lng = locationData['longitude'] as double?;
                        
                        return Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: GestureDetector(
                            onTap: () {
                              if (lat != null && lng != null && _mapController != null) {
                                _mapController!.animateCamera(
                                  CameraUpdate.newLatLng(LatLng(lat, lng)),
                                );
                              }
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF8F5FE8),
                                  width: 2,
                                ),
                              ),
                              child: ClipOval(
                                child: _buildCachedProfileImageWidget(profileImageUrl, 36),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CircularImagePainter extends CustomPainter {
  final ui.Image image;
  final double size;

  _CircularImagePainter(this.image, this.size);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final center = Offset(size / 2, size / 2);
    final radius = size / 2;
    
    // Create circular clipping path
    final clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.save();
    canvas.clipPath(clipPath);
    
    // Draw the image scaled to fit the circle
    final srcRect = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dstRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawImageRect(image, srcRect, dstRect, Paint());
    
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
