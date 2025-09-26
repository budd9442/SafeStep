import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/location_service.dart';

class NativeBackgroundLocationService {
  static Timer? _locationTimer;
  static bool _isRunning = false;
  static String? _currentSessionId;
  static const Duration _updateInterval = Duration(seconds: 10);
  static FlutterLocalNotificationsPlugin? _notifications;

  // Initialize the service
  static Future<bool> initialize() async {
    try {
      print('🚀 [NATIVE BACKGROUND] Initializing native background location service');

      // Initialize notifications
      _notifications = FlutterLocalNotificationsPlugin();
      
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      await _notifications!.initialize(initSettings);

      // Request permissions
      await _requestPermissions();

      print('✅ [NATIVE BACKGROUND] Service initialized successfully');
      return true;

    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Failed to initialize: $e');
      return false;
    }
  }

  // Request necessary permissions
  static Future<bool> _requestPermissions() async {
    try {
      print('🔐 [NATIVE BACKGROUND] Requesting permissions');

      // Location permissions
      final locationStatus = await Permission.location.request();
      final locationAlwaysStatus = await Permission.locationAlways.request();
      
      // Background app refresh (iOS)
      if (Platform.isIOS) {
        await Permission.appTrackingTransparency.request();
      }

      // Notification permissions
      await Permission.notification.request();

      final hasLocationPermission = locationStatus.isGranted && locationAlwaysStatus.isGranted;
      
      if (!hasLocationPermission) {
        print('❌ [NATIVE BACKGROUND] Location permissions not granted');
        return false;
      }

      print('✅ [NATIVE BACKGROUND] Permissions granted');
      return true;

    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Permission request failed: $e');
      return false;
    }
  }

  // Start background location tracking
  static Future<bool> startTracking() async {
    try {
      if (_isRunning) {
        print('⚠️ [NATIVE BACKGROUND] Service is already running');
        return true;
      }

      print('🚀 [NATIVE BACKGROUND] Starting native background location tracking');

      // Check if user is sharing location
      final isSharing = await _checkIfUserIsSharing();
      if (!isSharing) {
        print('❌ [NATIVE BACKGROUND] User is not sharing location');
        return false;
      }

      // Show persistent notification
      await _showLocationNotification();

      _isRunning = true;

      // Start location service with native background capabilities
      await _startNativeLocationService();

      // Start periodic updates
      _locationTimer = Timer.periodic(_updateInterval, (timer) {
        _updateLocation();
      });

      // Update location immediately
      await _updateLocation();

      print('✅ [NATIVE BACKGROUND] Native background location tracking started');
      return true;

    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Failed to start tracking: $e');
      return false;
    }
  }

  // Start native location service
  static Future<void> _startNativeLocationService() async {
    try {
      // Configure location settings for background tracking
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      );

      // Start location service
      await Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (Position position) {
          print('📍 [NATIVE BACKGROUND] Native location update: ${position.latitude}, ${position.longitude}');
          _handleNativeLocationUpdate(position);
        },
        onError: (error) {
          print('❌ [NATIVE BACKGROUND] Native location error: $error');
        },
      );

      print('✅ [NATIVE BACKGROUND] Native location service started');

    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Failed to start native location service: $e');
    }
  }

  // Handle native location updates
  static void _handleNativeLocationUpdate(Position position) {
    if (!_isRunning || _currentSessionId == null) return;

    // Convert to our LocationData format
    final locationData = LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp?.toIso8601String() ?? DateTime.now().toIso8601String(),
      altitude: position.altitude,
      speed: position.speed,
      heading: position.heading,
    );

    // Send to backend
    LocationService.sendLocationUpdate(
      sessionId: _currentSessionId!,
      locationData: locationData,
    ).then((response) {
      if (response.success) {
        print('✅ [NATIVE BACKGROUND] Location update sent successfully');
        _updateFirebaseLocation(locationData);
      } else {
        print('❌ [NATIVE BACKGROUND] Failed to send location update: ${response.message}');
      }
    }).catchError((error) {
      print('❌ [NATIVE BACKGROUND] Error sending location update: $error');
    });
  }

  // Show persistent notification
  static Future<void> _showLocationNotification() async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'location_tracking',
        'Location Tracking',
        channelDescription: 'SafeStep is tracking your location',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
        showWhen: false,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: false,
        presentBadge: false,
        presentSound: false,
      );

      const notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications!.show(
        1001,
        'SafeStep Location Tracking',
        'Your location is being shared with your contacts',
        notificationDetails,
      );

      print('✅ [NATIVE BACKGROUND] Location notification shown');

    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Failed to show notification: $e');
    }
  }

  // Stop background location tracking
  static Future<void> stopTracking() async {
    try {
      if (!_isRunning) {
        print('⚠️ [NATIVE BACKGROUND] Service is not running');
        return;
      }

      print('🛑 [NATIVE BACKGROUND] Stopping native background location tracking');

      _locationTimer?.cancel();
      _locationTimer = null;
      _isRunning = false;
      _currentSessionId = null;

      // Cancel notification
      await _notifications?.cancel(1001);

      print('✅ [NATIVE BACKGROUND] Native background location tracking stopped');

    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Error stopping tracking: $e');
    }
  }

  // Check if user is currently sharing location
  static Future<bool> _checkIfUserIsSharing() async {
    try {
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('isAuthenticated', isEqualTo: true)
          .limit(1)
          .get();

      if (usersQuery.docs.isEmpty) {
        return false;
      }

      final userDoc = usersQuery.docs.first;
      final userData = userDoc.data();
      final isSharing = userData['sharingLocation'] == true;
      final sessionId = userData['locationSessionId'];

      if (isSharing && sessionId != null) {
        _currentSessionId = sessionId;
        print('✅ [NATIVE BACKGROUND] User is sharing location, session: $sessionId');
        return true;
      }

      return false;

    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Error checking sharing status: $e');
      return false;
    }
  }

  // Update location and send to backend
  static Future<void> _updateLocation() async {
    try {
      // Check if we still have a valid session
      if (_currentSessionId == null) {
        final isSharing = await _checkIfUserIsSharing();
        if (!isSharing) {
          print('🛑 [NATIVE BACKGROUND] User stopped sharing, stopping tracking');
          await stopTracking();
          return;
        }
      }

      // Get current location
      final locationData = await LocationService.getCurrentLocation();
      if (locationData == null) {
        print('⚠️ [NATIVE BACKGROUND] Failed to get current location');
        return;
      }

      print('📍 [NATIVE BACKGROUND] Sending location update: ${locationData.latitude}, ${locationData.longitude}');

      // Send location update to backend
      final response = await LocationService.sendLocationUpdate(
        sessionId: _currentSessionId!,
        locationData: locationData,
      );

      if (response.success) {
        print('✅ [NATIVE BACKGROUND] Location update sent successfully');
        await _updateFirebaseLocation(locationData);
      } else {
        print('❌ [NATIVE BACKGROUND] Failed to send location update: ${response.message}');
        
        // If session is invalid, stop tracking
        if (response.message?.contains('not found') == true) {
          print('🛑 [NATIVE BACKGROUND] Session not found, stopping tracking');
          await stopTracking();
        }
      }

    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Error updating location: $e');
    }
  }

  // Update Firebase with latest location
  static Future<void> _updateFirebaseLocation(LocationData locationData) async {
    try {
      final usersQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('isAuthenticated', isEqualTo: true)
          .limit(1)
          .get();

      if (usersQuery.docs.isNotEmpty) {
        final userDoc = usersQuery.docs.first;
        await userDoc.reference.update({
          'lastKnownLocation': {
            'latitude': locationData.latitude,
            'longitude': locationData.longitude,
            'accuracy': locationData.accuracy,
            'timestamp': locationData.timestamp,
            'altitude': locationData.altitude,
            'speed': locationData.speed,
            'heading': locationData.heading,
          },
          'lastLocationUpdate': FieldValue.serverTimestamp(),
        });
        
        print('✅ [NATIVE BACKGROUND] Firebase location updated');
      }
    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Error updating Firebase location: $e');
    }
  }

  // Check if service is running
  static bool get isRunning => _isRunning;

  // Get current session ID
  static String? get currentSessionId => _currentSessionId;

  // Force location update (for testing)
  static Future<void> forceLocationUpdate() async {
    if (_isRunning) {
      await _updateLocation();
    }
  }

  // Restart tracking (useful when app comes back to foreground)
  static Future<void> restartTracking() async {
    print('🔄 [NATIVE BACKGROUND] Restarting tracking');
    await stopTracking();
    await Future.delayed(Duration(seconds: 1));
    await startTracking();
  }

  // Handle app lifecycle changes
  static Future<void> onAppResumed() async {
    print('📱 [NATIVE BACKGROUND] App resumed, checking tracking status');
    if (_isRunning) {
      await restartTracking();
    }
  }

  static Future<void> onAppPaused() async {
    print('📱 [NATIVE BACKGROUND] App paused, maintaining background tracking');
    // Native location service continues in background
  }
}
