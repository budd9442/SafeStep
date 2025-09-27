import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/location_service.dart';
import '../services/native_background_location_service.dart';

// Updated share location sheet content with backend integration
class _ShareLocationSheetContent extends StatefulWidget {
  const _ShareLocationSheetContent();

  @override
  State<_ShareLocationSheetContent> createState() => _ShareLocationSheetContentState();
}

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
      print('[SHARE LOCATION] Starting location sharing process');
      
      // Step 1: Get current location with timeout
      final locationData = await LocationService.getCurrentLocation()
          .timeout(const Duration(seconds: 10));
      if (locationData == null) {
        throw Exception('Unable to get current location. Please check location permissions.');
      }
      
      print('[SHARE LOCATION] Current location: ${locationData.latitude}, ${locationData.longitude}');
      
      // Step 2: Generate client ID
      final clientId = LocationService.generateClientId();
      
      print('[SHARE LOCATION] Client ID: $clientId');
      
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
      
      print('[SHARE LOCATION] Phone Number: $phoneNumber');
      
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
      ).timeout(const Duration(seconds: 15));
      
      if (!backendResponse.success) {
        throw Exception('Backend error: ${backendResponse.message}');
      }
      
      _sessionId = backendResponse.sessionId;
      print('[SHARE LOCATION] Backend session started: $_sessionId');
      
      // Step 5: Convert contact IDs to user IDs and send notifications
      final fromName = (userData['name'] ?? 'Someone').toString();
      final fromId = userDoc.id;
      final contactsCol = FirebaseFirestore.instance.collection('users');
      final List<String> actualUserIds = [];
      
      // Get contact details to find their phone numbers
      for (final contactId in _selectedContactIds) {
        try {
          final contactDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(userDoc.id)
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
              
              print('[SHARE LOCATION] Looking up user with formatted phone: $formattedPhone');
              
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
                  'sessionId': _sessionId,
                  'createdAt': FieldValue.serverTimestamp(),
                  'read': false,
                });
                print('[SHARE LOCATION] Notification sent to user: $targetUserId (phone: $contactPhone)');
              } else {
                // Try finding by document ID (user ID might be the phone number without tel: prefix)
                final phoneWithoutTel = formattedPhone.replaceAll('tel:', '');
                print('[SHARE LOCATION] Trying to find user by document ID: $phoneWithoutTel');
                
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(phoneWithoutTel)
                    .get();
                
                if (userDoc.exists) {
                  print('[SHARE LOCATION] Found user by document ID: $phoneWithoutTel');
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
                    'sessionId': _sessionId,
                    'createdAt': FieldValue.serverTimestamp(),
                    'read': false,
                  });
                  print('[SHARE LOCATION] Notification sent to user: $targetUserId (phone: $contactPhone)');
                } else {
                  print('[SHARE LOCATION] No user found for phone: $contactPhone');
                }
              }
            }
          }
        } catch (e) {
          print('[SHARE LOCATION] Failed to process contact $contactId: $e');
        }
      }
      
      // Update Firebase with actual user IDs instead of contact IDs
      final durationMap = {0: 'always', 1: '1h', 2: '8h'};
      await userDoc.reference.set({
        'shareLocationContacts': actualUserIds, // Store actual user IDs
        'shareLocationDuration': durationMap[_selectedDuration],
        'shareLocationUpdatedAt': FieldValue.serverTimestamp(),
        'sharingLocation': true,
        'locationSessionId': _sessionId,
        'locationClientId': clientId,
        'lastKnownLocation': {
          'latitude': locationData.latitude,
          'longitude': locationData.longitude,
          'accuracy': locationData.accuracy,
          'timestamp': locationData.timestamp,
        },
      }, SetOptions(merge: true));
      
      print('[SHARE LOCATION] Firebase updated with shareLocationContacts: $actualUserIds');
      print('[SHARE LOCATION] Location sharing started successfully');
      
      // Step 6: Start native background location tracking AFTER Firebase update
      // Add a small delay to ensure Firebase update is propagated
      await Future.delayed(const Duration(milliseconds: 500));
      
      try {
        final trackingStarted = await NativeBackgroundLocationService.startTracking(sessionId: _sessionId);
        if (trackingStarted) {
          print('[SHARE LOCATION] Native background location tracking started');
        } else {
          print('[SHARE LOCATION] Background tracking failed to start - user may not be sharing');
        }
      } catch (e) {
        print('[SHARE LOCATION] Failed to start native background tracking: $e');
      }
      
      // Show success message and close immediately
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location sharing started with ${_selectedContactIds.length} contact(s)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
        Navigator.pop(context);
      }
      
    } catch (e) {
      print('[SHARE LOCATION] Error starting location sharing: $e');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start location sharing: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    
    // Always reset loading state
    if (mounted) {
      setState(() => _sharingLocation = false);
    }
  }
}
