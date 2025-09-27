import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:safestep/views/map_view.dart';
import 'package:safestep/views/menu_view.dart';
import 'package:safestep/views/settings_view.dart';
import 'package:safestep/widgets/panic_button_widget.dart';
import 'package:safestep/views/safe_chat_view.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:safestep/services/sos_navigation_service.dart';
import 'package:safestep/services/local_session.dart';
import 'package:safestep/services/location_database.dart';
import 'package:safestep/services/agent_data_service.dart';
import 'package:safestep/views/auth/phone_auth_screen.dart';
import 'package:safestep/services/location_service.dart';
import 'package:safestep/services/native_background_location_service.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // bool _showMap = false; // No longer needed, always show map
  LatLng? _currentPosition;
  bool _loading = true;
  String? _error;
  int? _currentIndex; // null: Map, 0: Menu, 1: Settings
  StreamSubscription<Position>? _positionStreamSubscription;
  List<DangerZone> _dangerZones = [];
  StreamSubscription<QuerySnapshot>? _dangerZoneSubscription;
  StreamSubscription<QuerySnapshot>? _inboxSubscription;
  StreamSubscription<QuerySnapshot>? _sharedLocationSubscription;
  final GlobalKey<MapViewState> _mapViewKey = GlobalKey<MapViewState>();
  Map<String, Map<String, dynamic>> _sharedLocations = {};

  final TextEditingController _chatController = TextEditingController();

  void _onNavTap(int index) {
    setState(() {
      _currentIndex = index;
      // _showMap = false; // No longer needed
    });
  }

  Future<bool> _onWillPop() async {
    if (_currentIndex != null) {
      setState(() {
        _currentIndex = null;
      });
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _determinePosition();
    _listenToPositionStream();
    _listenToDangerZones();
    _listenToInboxNotifications();
    _listenToSharedLocations();
    _checkForExpiredSessions();
    _startAgentDataCollection();
    
    // Channel initialized globally in main.dart
  }

  void _listenToDangerZones() {
    // Listen to Firestore for live updates
    _dangerZoneSubscription = FirebaseFirestore.instance
        .collection('dangerzones')
        .snapshots()
        .listen((snapshot) {
      final zones = snapshot.docs.map((doc) {
        final data = doc.data();
        return DangerZone(
          LatLng((data['lat'] ?? 0.0) * 1.0, (data['lng'] ?? 0.0) * 1.0),
          (data['radius'] ?? 0.0) * 1.0,
          id: doc.id,
          description: data['description'] as String?,
        );
      }).toList();
       print('Danger zones updated: $zones'); // <-- Add this line
    
      setState(() {
        _dangerZones = zones;
      });
    });
  }

  void _listenToSharedLocations() async {
    try {
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null || localUserId.isEmpty) return;

      // Listen to users who are sharing location with current user
      _sharedLocationSubscription = FirebaseFirestore.instance
          .collection('users')
          .where('shareLocationContacts', arrayContains: localUserId)
          .where('sharingLocation', isEqualTo: true)
          .snapshots()
          .listen((snapshot) {
        print('🔍 [SHARED LOCATIONS] Query returned ${snapshot.docs.length} documents');
        final sharedLocations = <String, Map<String, dynamic>>{};
        
        for (final doc in snapshot.docs) {
          final data = doc.data();
          print('🔍 [SHARED LOCATIONS] Found user: ${doc.id}, sharingLocation: ${data['sharingLocation']}, shareLocationContacts: ${data['shareLocationContacts']}');
          final lastKnownLocation = data['lastKnownLocation'] as Map<String, dynamic>?;
          
          if (lastKnownLocation != null) {
            final lat = lastKnownLocation['latitude'] as double?;
            final lng = lastKnownLocation['longitude'] as double?;
            
            if (lat != null && lng != null) {
              sharedLocations[doc.id] = {
                'userId': doc.id,
                'name': data['name'] ?? 'Unknown',
                'profileImageUrl': data['profileImageUrl'],
                'latitude': lat,
                'longitude': lng,
                'timestamp': lastKnownLocation['timestamp'],
                'accuracy': lastKnownLocation['accuracy'],
              };
              print('✅ [SHARED LOCATIONS] Added location for user: ${doc.id} at $lat, $lng');
            }
          }
        }
        
        setState(() {
          _sharedLocations = sharedLocations;
        });
        
        print('📍 [SHARED LOCATIONS] Updated: ${sharedLocations.length} users sharing location');
      });
    } catch (e) {
      print('❌ [SHARED LOCATIONS] Error listening to shared locations: $e');
    }
  }

  Future<void> _focusOnSharedLocation(String fromUserId) async {
    try {
      // Get the shared location from the user's document
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(fromUserId)
          .get();
      
      if (userDoc.exists) {
        final data = userDoc.data()!;
        final lastKnownLocation = data['lastKnownLocation'] as Map<String, dynamic>?;
        
        if (lastKnownLocation != null) {
          final lat = lastKnownLocation['latitude'] as double?;
          final lng = lastKnownLocation['longitude'] as double?;
          
          if (lat != null && lng != null) {
            // Focus map on the shared location
            if (_mapViewKey.currentState != null) {
              // You can add a method to MapView to focus on a specific location
              print('📍 [FOCUS] Focusing on shared location: $lat, $lng');
            }
          }
        }
      }
    } catch (e) {
      print('❌ [FOCUS] Error focusing on shared location: $e');
    }
  }

  void _listenToInboxNotifications() async {
    try {
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null || localUserId.isEmpty) return;

      _inboxSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(localUserId)
          .collection('inbox')
          .where('read', isEqualTo: false)
          .snapshots()
          .listen((snapshot) async {
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final String type = (data['type'] ?? '').toString();
          if (type == 'share_location') {
            final String fromName = (data['fromName'] ?? 'Someone').toString();
            final String fromUserId = (data['fromUserId'] ?? '').toString();
            if (!mounted) continue;
            
            // Show modern notification popup
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF8F5FE8), Color(0xFF6C63FF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.location_on, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Location Shared',
                        style: GoogleFonts.lato(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF232946),
                        ),
                      ),
                    ),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$fromName is sharing their location with you',
                      style: GoogleFonts.lato(
                        fontSize: 16,
                        color: const Color(0xFF232946),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You can now see their location on the map',
                      style: GoogleFonts.lato(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // Mark as read
                      doc.reference.set({'read': true, 'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                    },
                    child: Text(
                      'Dismiss',
                      style: GoogleFonts.lato(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      // Mark as read
                      doc.reference.set({'read': true, 'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                      // Focus map on shared location
                      _focusOnSharedLocation(fromUserId);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8F5FE8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'View on Map',
                      style: GoogleFonts.lato(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
        }
      });
    } catch (_) {
      // ignore listener errors
    }
  }

  // Check for expired sessions periodically
  void _checkForExpiredSessions() {
    // Check every 30 seconds for expired sessions
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      try {
        final localUserId = await LocalSession.getCurrentUserId();
        if (localUserId == null) return;
        
        final activeSession = await LocationDatabase.getActiveSession(localUserId);
        if (activeSession != null) {
          // Check if session is still active on backend
          final response = await LocationService.getSessionStatus(activeSession['session_id']);
          if (!response.success || 
              response.sessionData?['isActive'] != true || 
              response.sessionData?['status'] != 'active') {
            
            print('⚠️ [HOME SCREEN] Session expired on backend, updating UI');
            
            // End local session
            await LocationDatabase.endSession(activeSession['session_id']);
            
            // Update Firebase to reflect stopped sharing
            await FirebaseFirestore.instance.collection('users').doc(localUserId).set({
              'sharingLocation': false,
              'shareLocationContacts': [],
              'shareLocationDuration': null,
              'shareLocationUpdatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
            
            // Stop background tracking
            await NativeBackgroundLocationService.stopTracking();
            
            if (mounted) {
              setState(() {}); // Refresh UI
            }
          }
        }
      } catch (e) {
        print('❌ [HOME SCREEN] Error checking expired sessions: $e');
      }
    });
  }

  Future<void> _startAgentDataCollection() async {
    try {
      await AgentDataService.startDataCollection();
      print('✅ [HOME SCREEN] Agent data collection started');
    } catch (e) {
      print('❌ [HOME SCREEN] Failed to start agent data collection: $e');
    }
  }

  void _listenToPositionStream() {
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen(
      (Position pos) {
        if (!mounted) return;
        setState(() {
          _currentPosition = LatLng(pos.latitude, pos.longitude);
          _loading = false;
        });
      },
      onError: (e) {
        if (!mounted) return;
        setState(() {
          _error = 'Failed to get location: $e';
          _loading = false;
        });
      },
    );
  }

  Future<void> _determinePosition() async {
    try {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        setState(() {
          _error = 'Location permissions are denied.';
          _loading = false;
        });
        return;
      }
      Position pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = LatLng(pos.latitude, pos.longitude);
        _loading = false;
      });
      // Subscribe to location updates
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen(
        (Position position) {
          setState(() {
            _currentPosition = LatLng(position.latitude, position.longitude);
          });
        },
        onError: (e) {
          setState(() {
            _error = 'Location update error: $e';
          });
        },
      );
    } catch (e) {
      setState(() {
        _error = 'Failed to get location: $e';
        _loading = false;
      });
    }
  }

  void _addDangerZone(LatLng center, double radius, {String? description}) {
    setState(() {
      _dangerZones.add(DangerZone(center, radius, description: description));
    });
  }

  void _onDangerZoneTap(DangerZone zone) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Danger Zone'),
        content: Text(zone.description ?? 'No description.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openSafeChatWithMessage(String message) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => SafeChatView(initialMessage: message, initialMessageRole: 'user'),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final tween = Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeInOut));
          return SlideTransition(position: animation.drive(tween), child: child);
        },
      ),
    );
  }

  Widget _buildChatInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        color: Colors.transparent,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(32),
          color: Colors.white,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: const Color(0xFFE0E0E0), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(fontSize: 16, color: Color(0xFF232946)),
                    decoration: const InputDecoration(
                      hintText: 'Whats on your mind...',
                      hintStyle: TextStyle(color: Color(0xFFB0AEB8)),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    minLines: 1,
                    maxLines: 3,
                    onSubmitted: (value) {
                      if (value.trim().isNotEmpty) {
                        _openSafeChatWithMessage(value.trim());
                        _chatController.clear();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF8F5FE8),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8F5FE8).withOpacity(0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 24),
                    splashRadius: 24,
                    onPressed: () {
                      final value = _chatController.text.trim();
                      if (value.isNotEmpty) {
                        _openSafeChatWithMessage(value);
                        _chatController.clear();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedChatBar() {
    final show = _currentIndex == null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          axis: Axis.vertical,
          child: child,
        ),
      ),
      child: show ? _buildChatInputBar() : const SizedBox.shrink(key: ValueKey('emptyChatBar')),
    );
  }

  void _onProfilePicChanged(String localPath) {
    _mapViewKey.currentState?.loadProfilePointerMarker(localPath);
  }

  Future<void> _logout() async {
    try {
      // Show confirmation dialog
      final bool? shouldLogout = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Logout'),
              ),
            ],
          );
        },
      );

      if (shouldLogout == true) {
        // Clear local session
        await LocalSession.clear();

        // Navigate back to auth screen
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const PhoneAuthScreen()),
            (route) => false,
          );
        }
      }
    } catch (e) {
      print('Error during logout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: ${e.toString()}')),
        );
      }
    }
  }

  void _openProfileSettings() {
    // Use the same navigation as the settings tile
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ProfileSettingsRouteProxy()),
    );
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _dangerZoneSubscription?.cancel();
    _inboxSubscription?.cancel();
    _sharedLocationSubscription?.cancel();
    SosNavigationService.dispose();
    AgentDataService.stopDataCollection();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          title: Row(
            children: [
              Image.asset(
                "assets/SafeStep.png",
                height: 40,
              ),
              const SizedBox(width: 6),
              const Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Safe',
                      style: TextStyle(
                        color: Color(0xFF8F5FE8),
                        fontWeight: FontWeight.bold,
                        fontFamily: "QuintessentialCustom",
                        fontSize: 20,
                      ),
                    ),
                    TextSpan(
                      text: 'Step',
                      style: TextStyle(
                        color: Color(0xFF8F5FE8),
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.person, color: Color(0xFF8F5FE8)),
              onSelected: (value) async {
                if (value == 'profile') {
                  _openProfileSettings();
                } else if (value == 'logout') {
                  await _logout();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'profile',
                  child: ListTile(
                    leading: Icon(Icons.settings),
                    title: Text('Settings'),
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'logout',
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Logout'),
                  ),
                ),
              ],
              tooltip: 'Account',
            ),
          ],
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFB39DDB), // purple top
                Color(0xFFD1C4E9),
                Color(0xFFE9E3F7),
                Color(0xFFF6F4FB),
                Color(0xFFD1C4E9),
                Color(0xFFB39DDB), // purple bottom
              ],
              stops: [0.0, 0.18, 0.5, 0.82, 0.92, 1.0],
            ),
          ),
          child: _currentIndex == null
              ? Stack(
                  children: [
                    // Map container in the background
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), // Match top and bottom gap
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Material(
                              elevation: 8,
                              borderRadius: BorderRadius.circular(24),
                              child: SizedBox(
                                height: 500,
                                width: double.infinity,
                                child: MapView(
                                  key: _mapViewKey,
                                  currentPosition: _currentPosition,
                                  loading: _loading,
                                  error: _error,
                                  dangerZones: _dangerZones.isEmpty ? null : _dangerZones,
                                  onDangerZoneTap: _onDangerZoneTap,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Foreground: ShareLocationCard/ActiveShareLocationPanel
                    Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: StreamBuilder<QuerySnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('users')
                                .where('isAuthenticated', isEqualTo: true)
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                                return ShareLocationCard(
                                  onShare: () => _showShareLocationSheet(context),
                                  onLocationIconTap: null,
                                );
                              }
                              final userDoc = snapshot.data!.docs.first;
                              final data = userDoc.data() as Map<String, dynamic>?;
                              final sharing = data != null && data['sharingLocation'] == true;
                              if (sharing) {
                                final List contacts = (data['shareLocationContacts'] ?? []) as List;
                                return ActiveShareLocationPanel(
                                  contactIds: contacts.cast<String>(),
                                  onLocationIconTap: null,
                                );
                              } else {
                                return ShareLocationCard(
                                  onShare: () => _showShareLocationSheet(context),
                                  onLocationIconTap: null,
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ],
                )
              : _currentIndex == 0
                  ? MenuView(
                      onFeatureOpen: (open) => setState(() => _featureOpen = open),
                      onAddDangerZone: _addDangerZone,
                      currentPosition: _currentPosition,
                    )
                  : SettingsView(onProfilePicChanged: _onProfilePicChanged),
        ),
        bottomNavigationBar: CustomBottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: _onNavTap,
        ),
      ),
    );
  }
}

// Panel shown when sharing location is active

class ActiveShareLocationPanel extends StatefulWidget {
  final List<String> contactIds;
  final VoidCallback? onLocationIconTap;
  const ActiveShareLocationPanel({required this.contactIds, this.onLocationIconTap, Key? key}) : super(key: key);

  @override
  State<ActiveShareLocationPanel> createState() => _ActiveShareLocationPanelState();
}

class _ActiveShareLocationPanelState extends State<ActiveShareLocationPanel> {
  bool _stopping = false;

  Future<void> _stopSharing() async {
    setState(() => _stopping = true);
    
    try {
      // Get local user ID
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null || localUserId.isEmpty) {
        print('❌ [STOP SHARING] No local session found');
        return;
      }

      // Get active session from SQLite
      final activeSession = await LocationDatabase.getActiveSession(localUserId);
      if (activeSession != null) {
        // End session in SQLite
        await LocationDatabase.endSession(activeSession['session_id']);
        print('✅ [STOP SHARING] SQLite session ended: ${activeSession['session_id']}');
      }

      // Update Firebase with sharing status
      await FirebaseFirestore.instance.collection('users').doc(localUserId).set({
        'sharingLocation': false,
        'shareLocationContacts': [],
        'shareLocationDuration': null,
        'shareLocationUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ [STOP SHARING] Firebase updated with stop status');
      
      // Force UI update to show the share location card
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ [STOP SHARING] Error stopping location sharing: $e');
    }
    
    if (mounted) setState(() => _stopping = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: widget.onLocationIconTap,
              child: CircleAvatar(
                radius: 30,
                backgroundColor: const Color(0xFF8F5FE8),
                child: const Icon(Icons.location_on, color: Colors.white, size: 32),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Sharing location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: Color(0xFF232946))),
                const SizedBox(height: 6),
                _ActiveContactAvatars(contactIds: widget.contactIds),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 18.0),
            child: ElevatedButton(
              onPressed: _stopping ? null : _stopSharing,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8F5FE8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                elevation: 0,
              ),
              child: _stopping
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Stop', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

// Widget to show avatars for shared contacts
class _ActiveContactAvatars extends StatelessWidget {
  final List<String> contactIds;
  const _ActiveContactAvatars({required this.contactIds});

  String _getSafeImageField(DocumentSnapshot doc) {
    try {
      final data = doc.data() as Map<String, dynamic>?;
      if (data != null) {
        // Check for URL-based profile picture fields first
        final profilePicUrl = data['profilePicUrl'] ?? data['profilePic'] ?? data['image'];
        if (profilePicUrl != null && profilePicUrl.isNotEmpty) {
          return profilePicUrl;
        }
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (contactIds.isEmpty) {
      return Row(
        children: [
          _TinyContactAvatar(icon: Icons.person, color: Color(0xFF8F5FE8)),
        ],
      );
    }
    
    return FutureBuilder<String?>(
      future: LocalSession.getCurrentUserId(),
      builder: (context, userIdSnapshot) {
        if (!userIdSnapshot.hasData || userIdSnapshot.data == null) {
          return Row(children: [for (var _ in contactIds) _TinyContactAvatar(icon: Icons.person, color: Color(0xFF8F5FE8))]);
        }
        
        final currentUserId = userIdSnapshot.data!;
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(currentUserId)
              .collection('contacts')
              .where(FieldPath.documentId, whereIn: contactIds.length > 10 ? contactIds.sublist(0, 10) : contactIds)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return Row(children: [for (var _ in contactIds) _TinyContactAvatar(icon: Icons.person, color: Color(0xFF8F5FE8))]);
            }
            final docs = snapshot.data!.docs;
            return Row(
              children: [
                for (final doc in docs)
                  Padding(
                    padding: const EdgeInsets.only(right: 4.0),
                    child: _ActiveContactAvatar(
                      name: doc['name'] ?? '',
                      image: _getSafeImageField(doc),
                    ),
                  ),
                if (docs.length < contactIds.length)
                  for (int i = docs.length; i < contactIds.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: _TinyContactAvatar(icon: Icons.person, color: Color(0xFF8F5FE8)),
                    ),
              ],
            );
          },
        );
      },
    );
  }
}


class ShareLocationCard extends StatelessWidget {
  final VoidCallback onShare;
  final VoidCallback? onLocationIconTap;
  const ShareLocationCard({required this.onShare, this.onLocationIconTap, super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.all(14.0),
            child: GestureDetector(
              onTap: onLocationIconTap,
              child: CircleAvatar(
                radius: 30,
                child: Icon(Icons.location_on_outlined, size: 32, color: Color(0xFFFFFFFF)),
                backgroundColor: Color(0xFF8F5FE8),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Share Location', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: Color(0xFF232946))),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _TinyContactAvatar(icon: Icons.person, color: Color(0xFF8F5FE8)),
                    const SizedBox(width: 4),
                    _TinyContactAvatar(icon: Icons.person, color: Color(0xFF6C63FF)),
                    const SizedBox(width: 4),
                    _TinyContactAvatar(icon: Icons.person, color: Color(0xFF8F5FE8)),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 18.0),
            child: ElevatedButton(
              onPressed: onShare,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8F5FE8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                elevation: 0,
              ),
              child: const Text('Share', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TinyContactAvatar extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _TinyContactAvatar({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 12,
      backgroundColor: color.withOpacity(0.15),
      child: Icon(icon, size: 16, color: color),
    );
  }
}

class _ActiveContactAvatar extends StatelessWidget {
  final String name;
  final String image;
  const _ActiveContactAvatar({required this.name, required this.image});

  Color _getColorForName(String name) {
    final colors = Colors.primaries;
    final hash = name.isNotEmpty ? name.codeUnits.reduce((a, b) => a + b) : 0;
    return colors[hash % colors.length].shade400;
  }

  @override
  Widget build(BuildContext context) {
    final bool hasImage = image.isNotEmpty;
    final String initial = name.isNotEmpty ? name.trim()[0].toUpperCase() : '';
    final Color? bgColor = hasImage ? null : _getColorForName(name);
    
    return CircleAvatar(
      radius: 12,
      backgroundColor: bgColor,
      backgroundImage: hasImage && image.startsWith('http') 
          ? NetworkImage(image)
          : hasImage 
              ? AssetImage(image) as ImageProvider
              : null,
      child: !hasImage
          ? Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            )
          : null,
    );
  }
}

void _showShareLocationSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return _ShareLocationSheetContent();
    },
  );
}

class _ShareLocationSheetContent extends StatefulWidget {
  @override
  State<_ShareLocationSheetContent> createState() => _ShareLocationSheetContentState();
}

class _ShareLocationSheetContentState extends State<_ShareLocationSheetContent> {
  Set<String> _selectedContactIds = {};
  String _search = '';
  int _selectedDuration = 1; // 0: Always, 1: 1 hour, 2: 8 hours
  bool _sharingLocation = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 32,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Select Contacts to Share Location',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
          ),
          const SizedBox(height: 18),
          TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search, color: Color(0xFF8F5FE8)),
              hintText: 'Search',
              filled: true,
              fillColor: const Color(0xFFF6F6F6),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) => setState(() => _search = val.trim().toLowerCase()),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 110,
            child: FutureBuilder<String?>(
              future: LocalSession.getCurrentUserId(),
              builder: (context, userIdSnapshot) {
                if (!userIdSnapshot.hasData || userIdSnapshot.data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final currentUserId = userIdSnapshot.data!;
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUserId)
                      .collection('contacts')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final contacts = snapshot.data!.docs;
                final filtered = _search.isEmpty
                    ? contacts
                    : contacts.where((c) => (c['name'] ?? '').toString().toLowerCase().contains(_search)).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No contacts found'));
                }
                return ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: filtered.length,
                  separatorBuilder: (context, i) => const SizedBox(width: 12),
                  itemBuilder: (context, i) {
                    final doc = filtered[i];
                    final name = doc['name'] ?? '';
                    final id = doc.id;
                    final selected = _selectedContactIds.contains(id);
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          if (selected) {
                            _selectedContactIds.remove(id);
                          } else {
                            _selectedContactIds.add(id);
                          }
                        });
                      },
                      child: _ContactAvatar(
                        name: name,
                        image: '',
                        selected: selected,
                      ),
                    );
                  },
                );
              },
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _DurationRadio(
                label: 'Always',
                value: 0,
                selected: _selectedDuration == 0,
                onChanged: (v) => setState(() => _selectedDuration = v!),
              ),
              _DurationRadio(
                label: '1 hour',
                value: 1,
                selected: _selectedDuration == 1,
                onChanged: (v) => setState(() => _selectedDuration = v!),
              ),
              _DurationRadio(
                label: '8 hours',
                value: 2,
                selected: _selectedDuration == 2,
                onChanged: (v) => setState(() => _selectedDuration = v!),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedContactIds.isNotEmpty && !_sharingLocation ? () async {
                await _startLocationSharing();
              } : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8F5FE8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _sharingLocation
                  ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startLocationSharing() async {
    setState(() => _sharingLocation = true);
    
    try {
      print('🚀 [SHARE LOCATION] Starting location sharing process');
      
      // Step 1: Get current location
      final locationData = await LocationService.getCurrentLocation();
      if (locationData == null) {
        throw Exception('Unable to get current location. Please check location permissions.');
      }
      
      print('📍 [SHARE LOCATION] Current location: ${locationData.latitude}, ${locationData.longitude}');
      
      // Step 2: Generate client ID
      final clientId = LocationService.generateClientId();
      
      print('📱 [SHARE LOCATION] Client ID: $clientId');
      
      // Step 3: Get user phone number using local session
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null || localUserId.isEmpty) {
        throw Exception('User not found');
      }

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(localUserId).get();
      if (!userDoc.exists) {
        throw Exception('User not found');
      }

      final userData = userDoc.data()!;
      final rawPhoneNumber = userData['phoneNumber'] ?? '';
      final phoneNumber = rawPhoneNumber.startsWith('tel:') ? rawPhoneNumber : 'tel:$rawPhoneNumber';
      
      print('📞 [SHARE LOCATION] Phone Number: $phoneNumber');
      
      // Step 4: Start backend location sharing session
      final backendResponse = await LocationService.startLocationSharing(
        clientId: clientId,
        phoneNumber: phoneNumber,
        metadata: {
          'startedBy': userData['name'] ?? 'Unknown',
          'purpose': 'share_location_with_contacts',
          'contactIds': _selectedContactIds.toList(),
          'duration': _selectedDuration,
          'flutterApp': true,
        },
      );
      
      if (!backendResponse.success) {
        throw Exception('Backend error: ${backendResponse.message}');
      }
      
      final sessionId = backendResponse.sessionId;
      if (sessionId == null) {
        throw Exception('Backend did not return session ID');
      }
      print('✅ [SHARE LOCATION] Backend session started: $sessionId');
      
      // Step 5: Create SQLite session and update Firebase with sharing status
      final durationMap = {0: 'always', 1: '1h', 2: '8h'};
      
      // Create session in SQLite
      await LocationDatabase.createSession(
        sessionId: sessionId,
        userId: localUserId,
        clientId: clientId,
        phoneNumber: phoneNumber,
        metadata: jsonEncode({
          'startedBy': (userData['name'] ?? 'Unknown').toString(),
          'purpose': 'share_location_with_contacts',
          'contactIds': _selectedContactIds.toList(),
          'duration': durationMap[_selectedDuration],
          'flutterApp': true,
        }),
      );
      
      print('✅ [SHARE LOCATION] Processing contacts and sending notifications...');
      
      // Force UI update to show the active sharing panel
      if (mounted) {
        setState(() {});
      }
      
      // Step 6: Convert contact IDs to user IDs and send notifications
      final fromName = (userData['name'] ?? 'Someone').toString();
      final fromId = localUserId;
      final contactsCol = FirebaseFirestore.instance.collection('users');
      final List<String> actualUserIds = [];
      
      // Get contact details to find their phone numbers
      for (final contactId in _selectedContactIds) {
        try {
          final contactDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(localUserId)
              .collection('contacts')
              .doc(contactId)
              .get();
          
          if (contactDoc.exists) {
            final contactData = contactDoc.data()!;
            final contactPhone = contactData['phone'] as String?;
            
            if (contactPhone != null) {
              // Format phone number to match user format
              String formattedPhone;
              if (contactPhone.startsWith('tel:')) {
                formattedPhone = contactPhone;
              } else if (contactPhone.startsWith('0')) {
                // Convert Sri Lankan format (0714555151) to international format (tel:94714555151)
                formattedPhone = 'tel:94${contactPhone.substring(1)}';
              } else if (contactPhone.startsWith('94')) {
                // Already has country code, just add tel: prefix
                formattedPhone = 'tel:$contactPhone';
              } else {
                // Assume it's a local number, add country code
                formattedPhone = 'tel:94$contactPhone';
              }
              
              print('🔍 [SHARE LOCATION] Looking up user with formatted phone: $formattedPhone');
              
              // Find user by phone number
              final userQuery = await FirebaseFirestore.instance
                  .collection('users')
                  .where('phoneNumber', isEqualTo: formattedPhone)
                  .limit(1)
                  .get();
              
              if (userQuery.docs.isNotEmpty) {
                final targetUserId = userQuery.docs.first.id;
                actualUserIds.add(targetUserId);
                
                // Send notification to the actual user
                await contactsCol
                    .doc(targetUserId)
                    .collection('inbox')
                    .add({
                  'type': 'share_location',
                  'fromUserId': fromId,
                  'fromName': fromName,
                  'sessionId': sessionId,
                  'createdAt': FieldValue.serverTimestamp(),
                  'read': false,
                });
                print('📨 [SHARE LOCATION] Notification sent to user: $targetUserId (phone: $contactPhone)');
              } else {
                // Try finding by document ID (user ID might be the phone number without tel: prefix)
                final phoneWithoutTel = formattedPhone.replaceAll('tel:', '');
                print('🔍 [SHARE LOCATION] Trying to find user by document ID: $phoneWithoutTel');
                
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(phoneWithoutTel)
                    .get();
                
                if (userDoc.exists) {
                  print('✅ [SHARE LOCATION] Found user by document ID: $phoneWithoutTel');
                  final targetUserId = userDoc.id;
                  actualUserIds.add(targetUserId);
                  
                  // Send notification to the actual user
                  await contactsCol
                      .doc(targetUserId)
                      .collection('inbox')
                      .add({
                    'type': 'share_location',
                    'fromUserId': fromId,
                    'fromName': fromName,
                    'sessionId': sessionId,
                    'createdAt': FieldValue.serverTimestamp(),
                    'read': false,
                  });
                  print('📨 [SHARE LOCATION] Notification sent to user: $targetUserId (phone: $contactPhone)');
                } else {
                  print('⚠️ [SHARE LOCATION] No user found for phone: $contactPhone');
                }
              }
            }
          }
        } catch (e) {
          print('❌ [SHARE LOCATION] Failed to process contact $contactId: $e');
        }
      }
      
      // Update Firebase with actual user IDs instead of contact IDs
      await FirebaseFirestore.instance.collection('users').doc(localUserId).set({
        'shareLocationContacts': actualUserIds, // Store actual user IDs
        'shareLocationDuration': durationMap[_selectedDuration],
        'shareLocationUpdatedAt': FieldValue.serverTimestamp(),
        'sharingLocation': true,
        'locationSessionId': sessionId,
        'locationClientId': clientId,
        'lastKnownLocation': {
          'latitude': locationData.latitude,
          'longitude': locationData.longitude,
          'accuracy': locationData.accuracy,
          'timestamp': locationData.timestamp,
        },
      }, SetOptions(merge: true));
      
      print('✅ [SHARE LOCATION] Firebase updated with shareLocationContacts: $actualUserIds');
      
      print('✅ [SHARE LOCATION] Location sharing started successfully');
      
      // Step 7: Start native background location tracking AFTER Firebase update
      // Add a small delay to ensure Firebase update is propagated
      await Future.delayed(const Duration(milliseconds: 500));
      
      try {
        final trackingStarted = await NativeBackgroundLocationService.startTracking(sessionId: sessionId);
        if (trackingStarted) {
          print('✅ [SHARE LOCATION] Native background location tracking started');
        } else {
          print('⚠️ [SHARE LOCATION] Background tracking failed to start - user may not be sharing');
        }
      } catch (e) {
        print('❌ [SHARE LOCATION] Failed to start native background tracking: $e');
      }
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location sharing started with ${_selectedContactIds.length} contact(s)'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'Test Updates',
              textColor: Colors.white,
              onPressed: () {
                NativeBackgroundLocationService.forceMultipleLocationUpdates();
              },
            ),
          ),
        );
      }
      
    } catch (e) {
      print('❌ [SHARE LOCATION] Error starting location sharing: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start location sharing: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    
    if (mounted) {
      Navigator.pop(context);
      setState(() => _sharingLocation = false);
    }
  }
}

class _ContactAvatar extends StatelessWidget {
  final String name;
  final String image;
  final bool selected;
  const _ContactAvatar({required this.name, required this.image, this.selected = false});

  Color _getColorForName(String name) {
    final colors = Colors.primaries;
    final hash = name.isNotEmpty ? name.codeUnits.reduce((a, b) => a + b) : 0;
    return colors[hash % colors.length].shade400;
  }

  @override
  Widget build(BuildContext context) {
    final bool hasImage = image.isNotEmpty;
    final String initial = name.isNotEmpty ? name.trim()[0].toUpperCase() : '';
    final Color? bgColor = hasImage ? null : _getColorForName(name);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 58, // 2*radius + border width*2
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: selected
                      ? Border.all(color: const Color(0xFF4CD964), width: 3)
                      : Border.all(color: Colors.transparent, width: 3),
                ),
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: bgColor,
                  backgroundImage: hasImage && image.startsWith('http') 
                      ? NetworkImage(image)
                      : hasImage 
                          ? AssetImage(image) as ImageProvider
                          : null,
                  child: !hasImage
                      ? Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        )
                      : null,
                ),
              ),
              if (selected)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFF4CD964),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(4),
                    child: const Icon(Icons.check, color: Colors.white, size: 18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }
}

class _DurationRadio extends StatelessWidget {
  final String label;
  final int value;
  final bool selected;
  final ValueChanged<int?>? onChanged;
  const _DurationRadio({required this.label, required this.value, this.selected = false, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Radio<int>(
          value: value,
          groupValue: selected ? value : null,
          onChanged: onChanged,
          activeColor: const Color(0xFF8F5FE8),
        ),
        Text(label, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}

class CustomBottomNavigationBar extends StatelessWidget {
  final int? currentIndex;
  final Function(int) onTap;

  const CustomBottomNavigationBar({
    required this.currentIndex,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 88,
            decoration: const BoxDecoration(
              border: Border(
                top: BorderSide(width: 1.0, color: Color(0xFFEDEDED)),
              ),
            ),
            child: BottomNavigationBar(
              currentIndex: currentIndex != null ? currentIndex! : 0,
              onTap: onTap,
              backgroundColor: Colors.white,
              items: const [
                BottomNavigationBarItem(
                  icon: Padding(
                    padding: EdgeInsets.symmetric(vertical: 5.0),
                    child: Icon(Icons.menu),
                  ),
                  label: 'Menu',
                ),
                BottomNavigationBarItem(
                  icon: Padding(
                    padding: EdgeInsets.symmetric(vertical: 5.0),
                    child: Icon(Icons.settings),
                  ),
                  label: 'Settings',
                ),
              ],
              selectedItemColor: const Color(0xFF8F5FE8),
              unselectedItemColor: Colors.grey,
              iconSize: 35,
              type: BottomNavigationBarType.fixed,
            ),
          ),
          Positioned(
            top: -41,
            left: MediaQuery.of(context).size.width / 2 - 40.5,
            child: const PanicButtonWidget(),
          ),
        ],
      ),
    );
  }
}

