import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:safestep/services/local_session.dart';
import 'package:safestep/services/sos_navigation_service.dart';
import 'package:safestep/views/auth/phone_auth_screen.dart';
import 'package:safestep/views/map_view.dart';
import 'package:safestep/views/menu_view.dart';
import 'package:safestep/views/safe_chat_view.dart';
import 'package:safestep/views/settings_view.dart';
import 'package:safestep/widgets/custom_widgets/panic_button_widget.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  LatLng? _currentPosition;
  bool _loading = true;
  String? _error;
  int? _currentIndex; // null: Map, 0: Menu, 1: Settings
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _featureOpen = false; // Track if a feature is open in MenuView
  List<DangerZone> _dangerZones = [];
  StreamSubscription<QuerySnapshot>? _dangerZoneSubscription;
  StreamSubscription<QuerySnapshot>? _inboxSubscription;
  final GlobalKey<MapViewState> _mapViewKey = GlobalKey<MapViewState>();

  final TextEditingController _chatController = TextEditingController();

  void _onNavTap(int index) {
    setState(() {
      _currentIndex = index;
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
    
    // Channel initialized globally in main.dart
  }

  void _listenToDangerZones() {
    // Listen to Firestore for live updates
    _dangerZoneSubscription = FirebaseFirestore.instance
        .collection('dangerzones')
        .snapshots()
        .listen((snapshot) {
      final zones = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
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

  void _listenToInboxNotifications() async {
    try {
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('isAuthenticated', isEqualTo: true)
          .limit(1)
          .get();

      if (usersQuery.docs.isEmpty) return;

      final userDoc = usersQuery.docs.first;
      _inboxSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(userDoc.id)
          .collection('inbox')
          .where('read', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) async {
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final String type = (data['type'] ?? '').toString();
          if (type == 'share_location') {
            final String fromName = (data['fromName'] ?? 'Someone').toString();
            if (!mounted) continue;
            // Show popup
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Location Share'),
                content: Text('$fromName is sharing their location with you'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
            // Mark as read
            await doc.reference.set({'read': true, 'readAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
          }
        }
      });
    } catch (_) {
      // ignore listener errors
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

  void _openSafeChatWithId(String chatId) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => SafeChatView(chatId: chatId),
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

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _dangerZoneSubscription?.cancel();
    _inboxSubscription?.cancel();
    SosNavigationService.dispose();
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
          leading: Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: CircleAvatar(
              backgroundColor: const Color(0xFF8F5FE8),
              child: Icon(Icons.shield, color: Colors.white),
            ),
          ),
          title: const Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Safe', style: TextStyle(color: Color(0xFF8F5FE8), fontWeight: FontWeight.bold)),
                TextSpan(text: 'Step', style: TextStyle(color: Color(0xFF232946), fontWeight: FontWeight.bold)),
              ],
            ),
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 1.2),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await _logout();
              },
              tooltip: 'Logout',
            ),
          ],
        ),
        body: Stack(
          children: [
            // Main content
            Column(
              children: [

                Expanded(
                  child: _currentIndex == null
                      ? Stack(
                          children: [
                            // Map background
                            MapView(
                              key: _mapViewKey,
                              currentPosition: _currentPosition,
                              loading: _loading,
                              error: _error,
                              dangerZones: _dangerZones.isEmpty ? null : _dangerZones,
                              onDangerZoneTap: _onDangerZoneTap,
                            ),
                            // Overlay ShareLocationCard or ActiveShareLocationPanel on top of map
                            Positioned(
                              top: 16,
                              left: 16,
                              right: 16,
                              child: StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance
                                    .collection('users')
                                    .where('isAuthenticated', isEqualTo: true)
                                    .snapshots(),
                                builder: (context, snapshot) {
                                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                                    return ShareLocationCard(onShare: () => _showShareLocationSheet(context));
                                  }
                                  final userDoc = snapshot.data!.docs.first;
                                  final data = userDoc.data() as Map<String, dynamic>?;
                                  final sharing = data != null && data['sharingLocation'] == true;
                                  if (sharing) {
                                    final List contacts = (data['shareLocationContacts'] ?? []) as List;
                                    return ActiveShareLocationPanel(
                                      contactIds: contacts.cast<String>(),
                                    );
                                  } else {
                                    return ShareLocationCard(onShare: () => _showShareLocationSheet(context));
                                  }
                                },
                              ),
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
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  child: SizedBox(height: 60), // Spacer for FAB
                ),
              ],
            ),
            // Custom bottom navigation bar with panic button
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomBottomNavigationBar(
                    currentIndex: _currentIndex,
                    onTap: _onNavTap,
                  ),
                  _buildAnimatedChatBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Panel shown when sharing location is active
class ActiveShareLocationPanel extends StatefulWidget {
  final List<String> contactIds;
  const ActiveShareLocationPanel({required this.contactIds, Key? key}) : super(key: key);

  @override
  State<ActiveShareLocationPanel> createState() => _ActiveShareLocationPanelState();
}

class _ActiveShareLocationPanelState extends State<ActiveShareLocationPanel> {
  bool _stopping = false;

  Future<void> _stopSharing() async {
    setState(() => _stopping = true);
    
    try {
      // Find the authenticated user
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('isAuthenticated', isEqualTo: true)
          .limit(1)
          .get();

      if (usersQuery.docs.isNotEmpty) {
        final userDoc = usersQuery.docs.first;
        await userDoc.reference.set({
          'sharingLocation': false,
          'shareLocationContacts': [],
          'shareLocationDuration': null,
          'shareLocationUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      print('Error stopping location sharing: $e');
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
            child: CircleAvatar(
              radius: 30,
              backgroundColor: const Color(0xFF8F5FE8),
              child: const Icon(Icons.location_on, color: Colors.white, size: 32),
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
    
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('isAuthenticated', isEqualTo: true)
          .limit(1)
          .snapshots()
          .asyncExpand((snapshot) {
            if (snapshot.docs.isEmpty) {
              return Stream<QuerySnapshot>.empty();
            }
            final userDoc = snapshot.docs.first;
            return FirebaseFirestore.instance
                .collection('users')
                .doc(userDoc.id)
                .collection('contacts')
                .where(FieldPath.documentId, whereIn: contactIds.length > 10 ? contactIds.sublist(0, 10) : contactIds)
                .snapshots();
          }),
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
  }
}

class ShareLocationCard extends StatelessWidget {
  final VoidCallback onShare;
  const ShareLocationCard({required this.onShare, super.key});

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
            child: CircleAvatar(
              radius: 30,
              child: Icon(Icons.location_on_outlined, size: 32, color: Color(0xFFFFFFFF)),
              backgroundColor: Color(0xFF8F5FE8),
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
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('isAuthenticated', isEqualTo: true)
                  .limit(1)
                  .snapshots()
                  .asyncExpand((snapshot) {
                    if (snapshot.docs.isEmpty) {
                      return Stream<QuerySnapshot>.empty();
                    }
                    final userDoc = snapshot.docs.first;
                    return FirebaseFirestore.instance
                        .collection('users')
                        .doc(userDoc.id)
                        .collection('contacts')
                        .orderBy('createdAt', descending: true)
                        .snapshots();
                  }),
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
                setState(() => _sharingLocation = true);
                
                try {
                  // Find the authenticated user
                  final usersQuery = await FirebaseFirestore.instance
                      .collection('users')
                      .where('isAuthenticated', isEqualTo: true)
                      .limit(1)
                      .get();

                  if (usersQuery.docs.isNotEmpty) {
                    final userDoc = usersQuery.docs.first;
                    final durationMap = {0: 'always', 1: '1h', 2: '8h'};
                    await userDoc.reference.set({
                      'shareLocationContacts': _selectedContactIds.toList(),
                      'shareLocationDuration': durationMap[_selectedDuration],
                      'shareLocationUpdatedAt': FieldValue.serverTimestamp(),
                      'sharingLocation': true,
                    }, SetOptions(merge: true));

                    // Send inbox notifications to each selected contact
                    final fromName = (userDoc.data()['name'] ?? 'Someone').toString();
                    final fromId = userDoc.id;
                    final contactsCol = FirebaseFirestore.instance.collection('users');
                    for (final contactId in _selectedContactIds) {
                      try {
                        await contactsCol
                            .doc(contactId)
                            .collection('inbox')
                            .add({
                          'type': 'share_location',
                          'fromUserId': fromId,
                          'fromName': fromName,
                          'createdAt': FieldValue.serverTimestamp(),
                          'read': false,
                        });
                      } catch (_) {}
                    }
                  }
                } catch (e) {
                  print('Error starting location sharing: $e');
                }
                
                if (mounted) Navigator.pop(context);
                setState(() => _sharingLocation = false);
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