import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';
import '../services/native_background_location_service.dart';

// Updated share location sheet content with backend integration
class _ShareLocationSheetContentState extends State<_ShareLocationSheetContent> {
  Set<String> _selectedContactIds = {};
  String _search = '';
  int _selectedDuration = 1; // 0: Always, 1: 1 hour, 2: 8 hours
  bool _sharingLocation = false;
  String? _sessionId; // Store the backend session ID

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
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userDoc = snapshot.data!.docs.first;
                final userData = userDoc.data() as Map<String, dynamic>;
                final contacts = List<Map<String, dynamic>>.from(userData['contacts'] ?? []);

                final filteredContacts = contacts.where((contact) {
                  final name = (contact['name'] ?? '').toString().toLowerCase();
                  return name.contains(_search);
                }).toList();

                return ListView.builder(
                  itemCount: filteredContacts.length,
                  itemBuilder: (context, index) {
                    final contact = filteredContacts[index];
                    final contactId = contact['userId'] ?? '';
                    final name = contact['name'] ?? 'Unknown';
                    final isSelected = _selectedContactIds.contains(contactId);

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSelected ? const Color(0xFF8F5FE8) : Colors.grey[300],
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(name),
                      trailing: Checkbox(
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedContactIds.add(contactId);
                            } else {
                              _selectedContactIds.remove(contactId);
                            }
                          });
                        },
                        activeColor: const Color(0xFF8F5FE8),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Duration',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: RadioListTile<int>(
                  title: const Text('Always'),
                  value: 0,
                  groupValue: _selectedDuration,
                  selected: _selectedDuration == 0,
                  onChanged: (v) => setState(() => _selectedDuration = v!),
                ),
              ),
              Expanded(
                child: RadioListTile<int>(
                  title: const Text('1 Hour'),
                  value: 1,
                  groupValue: _selectedDuration,
                  selected: _selectedDuration == 1,
                  onChanged: (v) => setState(() => _selectedDuration = v!),
                ),
              ),
              Expanded(
                child: RadioListTile<int>(
                  title: const Text('8 Hours'),
                  value: 2,
                  groupValue: _selectedDuration,
                  selected: _selectedDuration == 2,
                  onChanged: (v) => setState(() => _selectedDuration = v!),
                ),
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
      
      // Step 3: Get user phone number
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('isAuthenticated', isEqualTo: true)
          .limit(1)
          .get();

      if (usersQuery.docs.isEmpty) {
        throw Exception('User not found');
      }

      final userDoc = usersQuery.docs.first;
      final userData = userDoc.data();
      final phoneNumber = userData['phoneNumber'] ?? 'tel:+94712345678'; // Fallback
      
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
      
      _sessionId = backendResponse.sessionId;
      print('✅ [SHARE LOCATION] Backend session started: $_sessionId');
      
      // Step 5: Update Firebase with sharing status and session info
      final durationMap = {0: 'always', 1: '1h', 2: '8h'};
      await userDoc.reference.set({
        'shareLocationContacts': _selectedContactIds.toList(),
        'shareLocationDuration': durationMap[_selectedDuration],
        'shareLocationUpdatedAt': FieldValue.serverTimestamp(),
        'sharingLocation': true,
        'locationSessionId': _sessionId, // Store backend session ID
        'locationClientId': clientId,
        'lastKnownLocation': {
          'latitude': locationData.latitude,
          'longitude': locationData.longitude,
          'accuracy': locationData.accuracy,
          'timestamp': locationData.timestamp,
        },
      }, SetOptions(merge: true));

      print('✅ [SHARE LOCATION] Firebase updated with sharing status');
      
      // Step 6: Send inbox notifications to selected contacts
      final fromName = (userData['name'] ?? 'Someone').toString();
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
            'sessionId': _sessionId, // Include session ID in notification
            'createdAt': FieldValue.serverTimestamp(),
            'read': false,
          });
          print('📨 [SHARE LOCATION] Notification sent to contact: $contactId');
        } catch (e) {
          print('❌ [SHARE LOCATION] Failed to send notification to $contactId: $e');
        }
      }
      
      print('✅ [SHARE LOCATION] Location sharing started successfully');
      
      // Start native background location tracking
      try {
        await NativeBackgroundLocationService.startTracking();
        print('✅ [SHARE LOCATION] Native background location tracking started');
      } catch (e) {
        print('⚠️ [SHARE LOCATION] Failed to start native background tracking: $e');
      }
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location sharing started with ${_selectedContactIds.length} contact(s)'),
            backgroundColor: Colors.green,
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

// Updated stop sharing functionality with backend integration
class _ActiveShareLocationPanelState extends State<ActiveShareLocationPanel> {
  bool _stopping = false;

  Future<void> _stopSharing() async {
    setState(() => _stopping = true);
    
    try {
      print('🛑 [STOP SHARING] Starting stop sharing process');
      
      // Find the authenticated user
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('isAuthenticated', isEqualTo: true)
          .limit(1)
          .get();

      if (usersQuery.docs.isNotEmpty) {
        final userDoc = usersQuery.docs.first;
        final userData = userDoc.data();
        final sessionId = userData['locationSessionId'];
        
        // Stop backend session if it exists
        if (sessionId != null) {
          print('🛑 [STOP SHARING] Stopping backend session: $sessionId');
          final backendResponse = await LocationService.stopLocationSharing(
            sessionId: sessionId,
          );
          
          if (backendResponse.success) {
            print('✅ [STOP SHARING] Backend session stopped successfully');
          } else {
            print('⚠️ [STOP SHARING] Backend session stop failed: ${backendResponse.message}');
          }
        }
        
        // Stop native background location tracking
        try {
          await NativeBackgroundLocationService.stopTracking();
          print('✅ [STOP SHARING] Native background location tracking stopped');
        } catch (e) {
          print('⚠️ [STOP SHARING] Failed to stop native background tracking: $e');
        }
        
        // Update Firebase
        await userDoc.reference.set({
          'sharingLocation': false,
          'shareLocationContacts': [],
          'shareLocationDuration': null,
          'shareLocationUpdatedAt': FieldValue.serverTimestamp(),
          'locationSessionId': null, // Clear session ID
          'locationClientId': null,
        }, SetOptions(merge: true));
        
        print('✅ [STOP SHARING] Firebase updated');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location sharing stopped'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ [STOP SHARING] Error stopping location sharing: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping location sharing: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.green,
                  child: const Icon(Icons.location_on, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sharing Location',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      Text(
                        'With ${widget.contactIds.length} contact(s)',
                        style: TextStyle(color: Colors.grey[600], fontSize: 14),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _stopping ? null : _stopSharing,
                  icon: _stopping 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.stop, color: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
