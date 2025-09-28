import 'dart:async';
import 'dart:io';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../services/location_service.dart';
import 'local_session.dart';
import 'location_database.dart';

class NativeBackgroundLocationService {
  static Timer? _locationTimer;
  static bool _isRunning = false;
  static String? _currentSessionId;
  static FlutterLocalNotificationsPlugin? _notifications;
  static StreamSubscription<Position>? _locationSubscription;

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
  static Future<bool> startTracking({String? sessionId}) async {
    try {
      if (_isRunning) {
        print('⚠️ [NATIVE BACKGROUND] Service is already running, restarting with new session');
        print('🔄 [NATIVE BACKGROUND] Current session ID: $_currentSessionId');
        print('🔄 [NATIVE BACKGROUND] New session ID: $sessionId');
        await stopTracking();
        await Future.delayed(Duration(milliseconds: 500));
        print('✅ [NATIVE BACKGROUND] Service stopped, ready to restart');
      }

      print('🚀 [NATIVE BACKGROUND] Starting native background location tracking');

      // If sessionId is provided, use it directly
      if (sessionId != null) {
        _currentSessionId = sessionId;
        print('✅ [NATIVE BACKGROUND] Using provided session ID: $_currentSessionId');
      } else {
        // Check if user is sharing location with retry mechanism
        bool isSharing = false;
        int retryCount = 0;
        const maxRetries = 3;
        
        while (!isSharing && retryCount < maxRetries) {
          isSharing = await _checkIfUserIsSharing();
          if (!isSharing) {
            retryCount++;
            print('⏳ [NATIVE BACKGROUND] Retry $retryCount/$maxRetries - waiting for sharing status...');
            await Future.delayed(Duration(milliseconds: 500 * retryCount));
          }
        }
        
        if (!isSharing) {
          print('❌ [NATIVE BACKGROUND] User is not sharing location after $maxRetries retries');
          return false;
        }
      }

      // Show persistent notification
      await _showLocationNotification();

      _isRunning = true;

      // Start location service with native background capabilities
      print('🔄 [NATIVE BACKGROUND] Starting native location service...');
      await _startNativeLocationService();

      // Update location immediately
      print('🔄 [NATIVE BACKGROUND] Sending initial location update...');
      await _updateLocation();

      // Force a few location updates to test
      print('🔄 [NATIVE BACKGROUND] Forcing initial location updates...');
      for (int i = 0; i < 3; i++) {
        await Future.delayed(Duration(seconds: 2));
        await _updateLocation();
      }

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
      // Cancel existing subscription if any
      await _locationSubscription?.cancel();
      
      // Configure location settings for background tracking
      const locationSettings = LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10, // Update every 10 meters
      );

      print('🔄 [NATIVE BACKGROUND] Starting location stream...');

      // Start location service
      _locationSubscription = Geolocator.getPositionStream(
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
    print('📍 [NATIVE BACKGROUND] Location update received: ${position.latitude}, ${position.longitude}');
    print('🔍 [NATIVE BACKGROUND] Service running: $_isRunning, Session ID: $_currentSessionId');
    
    if (!_isRunning || _currentSessionId == null) {
      print('⚠️ [NATIVE BACKGROUND] Skipping location update - service not running or no session ID');
      return;
    }

    // Convert to our LocationData format
    final locationData = LocationData(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp.toIso8601String(),
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
        _saveLocationToSQLite(locationData);
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

      await _notifications?.show(
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
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      _isRunning = false;
      _currentSessionId = null;

      // Cancel notification
      await _notifications!.cancel(1001);

      print('✅ [NATIVE BACKGROUND] Native background location tracking stopped');

    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Error stopping tracking: $e');
    }
  }

  // Check if user is currently sharing location
  static Future<bool> _checkIfUserIsSharing() async {
    try {
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null || localUserId.isEmpty) {
        print('❌ [NATIVE BACKGROUND] No local session found');
        return false;
      }

      // Check SQLite for active session
      final activeSession = await LocationDatabase.getActiveSession(localUserId);
      if (activeSession != null) {
        // Verify session is still active on backend
        final isStillActive = await _verifySessionOnBackend(activeSession['session_id']);
        if (!isStillActive) {
          print('⚠️ [NATIVE BACKGROUND] Session expired on backend, stopping local session');
          await LocationDatabase.endSession(activeSession['session_id']);
          return false;
        }
        
        _currentSessionId = activeSession['session_id'];
        print('✅ [NATIVE BACKGROUND] User is sharing location, session: $_currentSessionId');
        return true;
      }

      print('❌ [NATIVE BACKGROUND] User is not sharing location or session ID missing');
      return false;

    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Error checking sharing status: $e');
      return false;
    }
  }

  // Verify if session is still active on backend
  static Future<bool> _verifySessionOnBackend(String sessionId) async {
    try {
      final response = await LocationService.getSessionStatus(sessionId);
      if (response.success && response.sessionData != null) {
        return response.sessionData!['isActive'] == true && response.sessionData!['status'] == 'active';
      }
      return false;
    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Error verifying session on backend: $e');
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
        await _saveLocationToSQLite(locationData);
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

  // Save location data to SQLite
  static Future<void> _saveLocationToSQLite(LocationData locationData) async {
    try {
      if (_currentSessionId == null) {
        print('❌ [NATIVE BACKGROUND] No session ID for location save');
        return;
      }

      await LocationDatabase.saveLocationData(
        sessionId: _currentSessionId!,
        latitude: locationData.latitude,
        longitude: locationData.longitude,
        accuracy: locationData.accuracy,
        altitude: locationData.altitude,
        speed: locationData.speed,
        heading: locationData.heading,
        timestamp: DateTime.parse(locationData.timestamp).millisecondsSinceEpoch,
      );

      print('✅ [NATIVE BACKGROUND] Location saved to SQLite');

    } catch (e) {
      print('❌ [NATIVE BACKGROUND] Error saving location to SQLite: $e');
    }
  }

  // Check if service is running
  static bool get isRunning => _isRunning;

  // Get current session ID
  static String? get currentSessionId => _currentSessionId;

  // Force location update (for testing)
  static Future<void> forceLocationUpdate() async {
    if (_isRunning) {
      print('🔄 [NATIVE BACKGROUND] Forcing location update...');
      await _updateLocation();
    } else {
      print('⚠️ [NATIVE BACKGROUND] Service not running, cannot force update');
    }
  }

  // Force multiple location updates for testing
  static Future<void> forceMultipleLocationUpdates() async {
    if (!_isRunning) {
      print('⚠️ [NATIVE BACKGROUND] Service not running, cannot force updates');
      return;
    }
    
    print('🔄 [NATIVE BACKGROUND] Forcing 5 location updates...');
    for (int i = 0; i < 5; i++) {
      print('📍 [NATIVE BACKGROUND] Force update ${i + 1}/5');
      await _updateLocation();
      await Future.delayed(Duration(seconds: 3));
    }
    print('✅ [NATIVE BACKGROUND] Completed forced location updates');
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

