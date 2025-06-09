import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:safestep/views/map_view.dart';
import 'package:safestep/views/menu_view.dart';
import 'package:safestep/views/settings_view.dart';
import 'package:safestep/widgets/custom_widgets/panic_button_widget.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LatLng? _currentPosition;
  bool _loading = true;
  String? _error;
  int? _currentIndex; // null: Map, 0: Menu, 1: Settings
  StreamSubscription<Position>? _positionStreamSubscription;
  bool _featureOpen = false; // Track if a feature is open in MenuView
  List<DangerZone> _dangerZones = [];

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
  }

  void _listenToPositionStream() {
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen(
      (Position pos) {
        setState(() {
          _currentPosition = LatLng(pos.latitude, pos.longitude);
          _loading = false;
        });
      },
      onError: (e) {
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

  void _addDangerZone(LatLng center, double radius) {
    setState(() {
      _dangerZones.add(DangerZone(center, radius));
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
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
        ),
        body: Stack(
          children: [
            // Main content
            Column(
              children: [
                // Only show ShareLocationCard above menu grid (not when feature is open)
                if (_currentIndex == 0 && !_featureOpen)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: ShareLocationCard(onShare: () => _showShareLocationSheet(context)),
                  ),
                Expanded(
                  child: _currentIndex == null
                      ? Stack(
                          children: [
                            // Map background
                            MapView(
                              currentPosition: _currentPosition,
                              loading: _loading,
                              error: _error,
                              dangerZones: _dangerZones.isEmpty ? null : _dangerZones,
                            ),
                            // Overlay ShareLocationCard on top of map
                            Positioned(
                              top: 16,
                              left: 16,
                              right: 16,
                              child: ShareLocationCard(onShare: () => _showShareLocationSheet(context)),
                            ),
                          ],
                        )
                      : _currentIndex == 0
                          ? MenuView(
                              onFeatureOpen: (open) => setState(() => _featureOpen = open),
                              onAddDangerZone: _addDangerZone,
                              currentPosition: _currentPosition,
                            )
                          : const SettingsView(),
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
              child: CustomBottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: _onNavTap,
              ),
            ),
          ],
        ),
      ),
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
                const SizedBox(height: 4),
                Row(
                  children: [
                    _TinyContactAvatar(icon: Icons.person, color: Color(0xFF8F5FE8)),
                    const SizedBox(width: 4),
                    _TinyContactAvatar(icon: Icons.person, color: Color(0xFF6C63FF)),
                    const SizedBox(width: 4),
                    _TinyContactAvatar(icon: Icons.person, color: Color(0xFFE0006A)),
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

void _showShareLocationSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
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
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 90,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _ContactAvatar(name: 'Faria', image: 'assets/faria.jpg', selected: true),
                  _ContactAvatar(name: 'Binita', image: 'assets/binita.jpg', selected: true),
                  _ContactAvatar(name: 'Trisha', image: 'assets/trisha.jpg', selected: true),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _DurationRadio(label: 'Always', value: 0),
                _DurationRadio(label: '1 hour', value: 1, selected: true),
                _DurationRadio(label: '8 hours', value: 2),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE0006A),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Continue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.white)),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _ContactAvatar extends StatelessWidget {
  final String name;
  final String image;
  final bool selected;
  const _ContactAvatar({required this.name, required this.image, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: AssetImage(image),
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
          const SizedBox(height: 6),
          Text(name, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

class _DurationRadio extends StatelessWidget {
  final String label;
  final int value;
  final bool selected;
  const _DurationRadio({required this.label, required this.value, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Radio<int>(
          value: value,
          groupValue: selected ? value : null,
          onChanged: (_) {},
          activeColor: const Color(0xFFE0006A),
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

