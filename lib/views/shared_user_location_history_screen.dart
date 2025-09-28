import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class SharedUserLocationHistoryScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? profileImageUrl;
  final LatLng currentLocation;

  const SharedUserLocationHistoryScreen({
    Key? key,
    required this.userId,
    required this.userName,
    this.profileImageUrl,
    required this.currentLocation,
  }) : super(key: key);

  @override
  State<SharedUserLocationHistoryScreen> createState() => _SharedUserLocationHistoryScreenState();
}

class _SharedUserLocationHistoryScreenState extends State<SharedUserLocationHistoryScreen> {
  List<Map<String, dynamic>> _locationHistory = [];
  bool _isLoading = true;
  String? _error;
  Set<Polyline> _polylines = {};
  Timer? _updateTimer;
  GoogleMapController? _mapController;

  @override
  void initState() {
    super.initState();
    
    _loadLocationHistory();
    
    // Start real-time updates every 10 seconds - only update data, not UI
    _updateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _updateLocationDataOnly();
    });
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  String? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    
    try {
      if (timestamp is String) {
        return timestamp;
      } else if (timestamp is Map<String, dynamic>) {
        // Handle Firestore Timestamp format
        final seconds = timestamp['_seconds'] as int?;
        if (seconds != null) {
          final dateTime = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
          return dateTime.toIso8601String();
        }
      }
    } catch (e) {
      print('⚠️ [LOCATION HISTORY] Error parsing timestamp: $e');
    }
    
    return null;
  }

  Future<void> _loadLocationHistory() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      print('🔍 [LOCATION HISTORY] Loading location history for user: ${widget.userId}');

      List<Map<String, dynamic>> allLocations = [];

      // Get location history from backend API
      // First, we need to find active sessions for this user
      final sessionsResponse = await http.get(
        Uri.parse('http://budd.systems:9442/api/location/sessions'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (sessionsResponse.statusCode == 200) {
        final sessionsData = json.decode(sessionsResponse.body);
        final sessions = sessionsData['data']['sessionsData'] as List;
        
        print('📊 [LOCATION HISTORY] Found ${sessions.length} active sessions');
        
        // Filter sessions for this user
        final userSessions = sessions.where((session) => 
          session['phoneNumber']?.contains(widget.userId) == true ||
          session['clientId']?.contains(widget.userId) == true
        ).toList();
        
        print('🔍 [LOCATION HISTORY] Found ${userSessions.length} sessions for user ${widget.userId}');

        for (var session in userSessions) {
          final sessionId = session['sessionId'] as String;
          print('🔍 [LOCATION HISTORY] Getting location data for session: $sessionId');
          
          // Get location history from API
          final historyResponse = await http.get(
            Uri.parse('http://budd.systems:9442/api/location/history/$sessionId?limit=100'),
            headers: {'Content-Type': 'application/json'},
          ).timeout(const Duration(seconds: 10));
          
          if (historyResponse.statusCode == 200) {
            final historyData = json.decode(historyResponse.body);
            final history = historyData['data']['history'] as List;
            
            print('📍 [LOCATION HISTORY] Found ${history.length} location points for session $sessionId');
            
            for (var location in history) {
              allLocations.add({
                'latitude': (location['latitude'] as num).toDouble(),
                'longitude': (location['longitude'] as num).toDouble(),
                'timestamp': _parseTimestamp(location['timestamp']) ?? _parseTimestamp(location['receivedAt']) ?? DateTime.now().toIso8601String(),
                'accuracy': location['accuracy'] != null ? (location['accuracy'] as num).toDouble() : null,
                'sessionId': sessionId,
                'source': 'api',
              });
              print('✅ [LOCATION HISTORY] Added location: ${location['latitude']}, ${location['longitude']} from session: $sessionId');
            }
          } else {
            print('⚠️ [LOCATION HISTORY] Failed to get history for session $sessionId: ${historyResponse.statusCode}');
          }
        }
      } else {
        print('⚠️ [LOCATION HISTORY] Failed to get sessions: ${sessionsResponse.statusCode}');
      }
      
      print('📍 [LOCATION HISTORY] Found ${allLocations.length} location records for user ${widget.userId}');

      // If no API data found, try to get from user's lastKnownLocation as fallback
      if (allLocations.isEmpty) {
        print('⚠️ [LOCATION HISTORY] No API location data found, trying Firebase user document...');
        
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .get();

        if (userDoc.exists) {
          final userData = userDoc.data()!;
          final lastKnownLocation = userData['lastKnownLocation'] as Map<String, dynamic>?;
          
          if (lastKnownLocation != null) {
            allLocations.add({
              'latitude': (lastKnownLocation['latitude'] as num).toDouble(),
              'longitude': (lastKnownLocation['longitude'] as num).toDouble(),
              'timestamp': lastKnownLocation['timestamp'] ?? DateTime.now().toIso8601String(),
              'accuracy': lastKnownLocation['accuracy'] != null ? (lastKnownLocation['accuracy'] as num).toDouble() : null,
              'sessionId': 'current',
              'source': 'firebase_fallback',
            });
            print('📍 [LOCATION HISTORY] Found last known location from Firebase user document');
          }
        }
      }

      // Sort by timestamp (oldest first for timeline)
      allLocations.sort((a, b) => 
        DateTime.parse(a['timestamp']).compareTo(DateTime.parse(b['timestamp'])));

      print('📈 [LOCATION HISTORY] Total location points: ${allLocations.length}');

      setState(() {
        _locationHistory = allLocations;
        _isLoading = false;
      });

      _updateMapMarkers();
    } catch (e) {
      print('❌ [LOCATION HISTORY] Error loading location history: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _updateLocationDataOnly() async {
    try {
      print('🔄 [LOCATION HISTORY] Updating location data (silent update)');

      List<Map<String, dynamic>> allLocations = [];

      // Get location history from backend API
      final sessionsResponse = await http.get(
        Uri.parse('http://budd.systems:9442/api/location/sessions'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      if (sessionsResponse.statusCode == 200) {
        final sessionsData = json.decode(sessionsResponse.body);
        final sessions = sessionsData['data']['sessionsData'] as List;
        
        // Filter sessions for this user
        final userSessions = sessions.where((session) => 
          session['phoneNumber']?.contains(widget.userId) == true ||
          session['clientId']?.contains(widget.userId) == true
        ).toList();

        for (var session in userSessions) {
          final sessionId = session['sessionId'] as String;
          
          // Get location history from API
          final historyResponse = await http.get(
            Uri.parse('http://budd.systems:9442/api/location/history/$sessionId?limit=100'),
            headers: {'Content-Type': 'application/json'},
          ).timeout(const Duration(seconds: 10));
          
          if (historyResponse.statusCode == 200) {
            final historyData = json.decode(historyResponse.body);
            final history = historyData['data']['history'] as List;
            
            for (var location in history) {
              allLocations.add({
                'latitude': (location['latitude'] as num).toDouble(),
                'longitude': (location['longitude'] as num).toDouble(),
                'timestamp': _parseTimestamp(location['timestamp']) ?? _parseTimestamp(location['receivedAt']) ?? DateTime.now().toIso8601String(),
                'accuracy': location['accuracy'] != null ? (location['accuracy'] as num).toDouble() : null,
                'sessionId': sessionId,
                'source': 'api',
              });
            }
          }
        }
      }

      // Sort by timestamp (oldest first for timeline)
      allLocations.sort((a, b) => 
        DateTime.parse(a['timestamp']).compareTo(DateTime.parse(b['timestamp'])));

      // Only update if data has changed
      if (allLocations.length != _locationHistory.length) {
        print('📈 [LOCATION HISTORY] Data changed: ${_locationHistory.length} -> ${allLocations.length} points');
        
        setState(() {
          _locationHistory = allLocations;
        });
        
        _updateMapMarkers();
      }
    } catch (e) {
      print('⚠️ [LOCATION HISTORY] Silent update failed: $e');
      // Don't show error to user for silent updates
    }
  }

  void _updateMapMarkers() {
    final polylines = <Polyline>{};

    if (_locationHistory.isNotEmpty) {
      // Create polyline connecting all points to show the path
      if (_locationHistory.length > 1) {
        final points = _locationHistory.map((location) => 
          LatLng(location['latitude'], location['longitude'])).toList();
        
        // Main path polyline
        polylines.add(
          Polyline(
            polylineId: const PolylineId('location_path'),
            points: points,
            color: const Color(0xFF8F5FE8),
            width: 4,
            patterns: [PatternItem.dash(20), PatternItem.gap(10)],
            jointType: JointType.round,
            endCap: Cap.roundCap,
            startCap: Cap.roundCap,
          ),
        );
      }
    }

    setState(() {
      _polylines = polylines;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF8F5FE8),
                  Color(0xFFE9E4F6),
                  Color(0xFFF8F9FF),
                ],
              ),
            ),
          ),
          // Content
          Column(
            children: [
              // Modern App Bar
              _buildModernAppBar(),
              // Map and History Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? _buildErrorWidget()
                        : _buildContent(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 20,
        right: 20,
        bottom: 16,
      ),
      child: Row(
        children: [
          // Back button
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(12), 
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF8F5FE8)),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          const SizedBox(width: 16),
          // Profile info
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Profile image with error handling
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF8F5FE8),
                    child: widget.profileImageUrl != null && widget.profileImageUrl!.isNotEmpty
                        ? ClipOval(
                            child: Image.network(
                              '${widget.profileImageUrl!}?t=${DateTime.now().millisecondsSinceEpoch}',
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Text(
                                  widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : 'U',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              },
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return const SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        : Text(
                            widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : 'U',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  // User info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.userName,
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF2D3748),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${_locationHistory.length} points • Live path',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF718096),
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
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

  Widget _buildErrorWidget() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red[400],
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load location history',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2D3748),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: const Color(0xFF718096),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadLocationHistory,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8F5FE8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Retry',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        // Map
        Expanded(
          flex: 3,
          child: Container(
            margin: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GoogleMap(
                onMapCreated: (GoogleMapController controller) {
                  _mapController = controller;
                },
                initialCameraPosition: CameraPosition(
                  target: widget.currentLocation,
                  zoom: 16.0,
                ),
                polylines: _polylines,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
                scrollGesturesEnabled: true,
                zoomGesturesEnabled: true,
                tiltGesturesEnabled: true,
                rotateGesturesEnabled: true,
              ),
            ),
          ),
        ),
        // Timeline
        Expanded(
          flex: 2,
          child: Container(
            margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Color(0xFFE2E8F0),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.timeline,
                        color: const Color(0xFF8F5FE8),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Location Path & Timeline',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF2D3748),
                        ),
                      ),
                      const Spacer(),
                      // Simple zoom button
                      IconButton(
                        icon: Icon(
                          Icons.zoom_out_map,
                          color: const Color(0xFF8F5FE8),
                          size: 20,
                        ),
                        onPressed: () {
                          if (_mapController != null) {
                            _mapController!.animateCamera(
                              CameraUpdate.newCameraPosition(
                                CameraPosition(
                                  target: widget.currentLocation,
                                  zoom: 16.0,
                                ),
                              ),
                            );
                          }
                        },
                        tooltip: 'Zoom to location',
                      ),
                    ],
                  ),
                ),
                // Timeline list
                Expanded(
                  child: _locationHistory.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.location_off,
                                color: Colors.grey[400],
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No location history available',
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _locationHistory.length,
                          itemBuilder: (context, index) {
                            final location = _locationHistory[index];
                            final timestamp = DateTime.parse(location['timestamp']);
                            final isLast = index == _locationHistory.length - 1;
                            
                            return _buildTimelineItem(
                              location,
                              timestamp,
                              isLast,
                              index,
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineItem(Map<String, dynamic> location, DateTime timestamp, bool isLast, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: isLast ? const Color(0xFF8F5FE8) : Colors.green[400],
                  shape: BoxShape.circle,
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 40,
                  color: Colors.grey[300],
                ),
            ],
          ),
          const SizedBox(width: 16),
          // Content
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.grey[200]!,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateFormat('MMM dd, yyyy • HH:mm:ss').format(timestamp),
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF8F5FE8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${location['latitude'].toStringAsFixed(6)}, ${location['longitude'].toStringAsFixed(6)}',
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF2D3748),
                    ),
                  ),
                  if (location['accuracy'] != null)
                    Text(
                      'Accuracy: ${location['accuracy'].toStringAsFixed(1)}m',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: const Color(0xFF718096),
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
