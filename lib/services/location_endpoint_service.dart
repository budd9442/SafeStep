import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../services/location_service.dart';

class LocationEndpointService {
  static HttpServer? _server;
  static bool _isRunning = false;
  static int _port = 3001; // Default port for the Flutter app's location endpoint
  static Timer? _locationUpdateTimer;
  static LocationData? _currentLocation;

  // Start the location endpoint server
  static Future<bool> startServer({int port = 3001}) async {
    try {
      if (_isRunning) {
        print('⚠️ [LOCATION ENDPOINT] Server is already running');
        return true;
      }

      _port = port;
      print('🚀 [LOCATION ENDPOINT] Starting server on port $_port');

      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, _port);
      _isRunning = true;

      print('✅ [LOCATION ENDPOINT] Server started successfully on http://localhost:$_port');

      // Start periodic location updates
      _startLocationUpdates();

      // Handle incoming requests
      _server!.listen((HttpRequest request) {
        _handleRequest(request);
      });

      return true;
    } catch (e) {
      print('❌ [LOCATION ENDPOINT] Failed to start server: $e');
      return false;
    }
  }

  // Stop the location endpoint server
  static Future<void> stopServer() async {
    try {
      if (!_isRunning) {
        print('⚠️ [LOCATION ENDPOINT] Server is not running');
        return;
      }

      print('🛑 [LOCATION ENDPOINT] Stopping server');

      _locationUpdateTimer?.cancel();
      await _server?.close();
      _server = null;
      _isRunning = false;

      print('✅ [LOCATION ENDPOINT] Server stopped successfully');
    } catch (e) {
      print('❌ [LOCATION ENDPOINT] Error stopping server: $e');
    }
  }

  // Check if server is running
  static bool get isRunning => _isRunning;

  // Get server URL
  static String get serverUrl => 'http://localhost:$_port';

  // Start periodic location updates
  static void _startLocationUpdates() {
    print('📍 [LOCATION ENDPOINT] Starting periodic location updates');
    
    // Update location immediately
    _updateLocation();
    
    // Update location every 5 seconds
    _locationUpdateTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _updateLocation();
    });
  }

  // Update current location
  static Future<void> _updateLocation() async {
    try {
      final locationData = await LocationService.getCurrentLocation();
      if (locationData != null) {
        _currentLocation = locationData;
        print('📍 [LOCATION ENDPOINT] Location updated: ${locationData.latitude}, ${locationData.longitude}');
      } else {
        print('⚠️ [LOCATION ENDPOINT] Failed to get current location');
      }
    } catch (e) {
      print('❌ [LOCATION ENDPOINT] Error updating location: $e');
    }
  }

  // Handle HTTP requests
  static void _handleRequest(HttpRequest request) {
    try {
      print('📡 [LOCATION ENDPOINT] Request: ${request.method} ${request.uri.path}');

      // Set CORS headers
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
      request.response.headers.add('Content-Type', 'application/json');

      // Handle OPTIONS requests (CORS preflight)
      if (request.method == 'OPTIONS') {
        request.response.statusCode = 200;
        request.response.close();
        return;
      }

      // Handle GET requests to /api/location
      if (request.method == 'GET' && request.uri.path == '/api/location') {
        _handleLocationRequest(request);
        return;
      }

      // Handle GET requests to /health
      if (request.method == 'GET' && request.uri.path == '/health') {
        _handleHealthRequest(request);
        return;
      }

      // Handle POST requests to /api/simulate-offline
      if (request.method == 'POST' && request.uri.path == '/api/simulate-offline') {
        _handleSimulateOfflineRequest(request);
        return;
      }

      // Handle POST requests to /api/simulate-online
      if (request.method == 'POST' && request.uri.path == '/api/simulate-online') {
        _handleSimulateOnlineRequest(request);
        return;
      }

      // 404 for unknown paths
      request.response.statusCode = 404;
      request.response.write(jsonEncode({
        'error': 'Not Found',
        'message': 'The requested endpoint does not exist',
        'path': request.uri.path,
      }));
      request.response.close();

    } catch (e) {
      print('❌ [LOCATION ENDPOINT] Error handling request: $e');
      try {
        request.response.statusCode = 500;
        request.response.write(jsonEncode({
          'error': 'Internal Server Error',
          'message': e.toString(),
        }));
        request.response.close();
      } catch (_) {
        // Ignore errors when trying to close response
      }
    }
  }

  // Handle location requests
  static void _handleLocationRequest(HttpRequest request) {
    try {
      if (_currentLocation == null) {
        print('❌ [LOCATION ENDPOINT] No location data available');
        request.response.statusCode = 503;
        request.response.write(jsonEncode({
          'error': 'Service Unavailable',
          'message': 'Location data not available',
        }));
        request.response.close();
        return;
      }

      print('📍 [LOCATION ENDPOINT] Returning location data');
      
      request.response.statusCode = 200;
      request.response.write(jsonEncode({
        'success': true,
        'latitude': _currentLocation!.latitude,
        'longitude': _currentLocation!.longitude,
        'accuracy': _currentLocation!.accuracy,
        'timestamp': _currentLocation!.timestamp,
        'altitude': _currentLocation!.altitude,
        'speed': _currentLocation!.speed,
        'heading': _currentLocation!.heading,
      }));
      request.response.close();

    } catch (e) {
      print('❌ [LOCATION ENDPOINT] Error handling location request: $e');
      request.response.statusCode = 500;
      request.response.write(jsonEncode({
        'error': 'Internal Server Error',
        'message': e.toString(),
      }));
      request.response.close();
    }
  }

  // Handle health check requests
  static void _handleHealthRequest(HttpRequest request) {
    try {
      request.response.statusCode = 200;
      request.response.write(jsonEncode({
        'status': 'OK',
        'service': 'Flutter Location Endpoint',
        'timestamp': DateTime.now().toIso8601String(),
        'currentLocation': _currentLocation?.toJson(),
        'port': _port,
      }));
      request.response.close();
    } catch (e) {
      print('❌ [LOCATION ENDPOINT] Error handling health request: $e');
      request.response.statusCode = 500;
      request.response.write(jsonEncode({
        'error': 'Internal Server Error',
        'message': e.toString(),
      }));
      request.response.close();
    }
  }

  // Handle simulate offline requests
  static void _handleSimulateOfflineRequest(HttpRequest request) {
    try {
      print('🔌 [LOCATION ENDPOINT] Simulating offline state');
      request.response.statusCode = 200;
      request.response.write(jsonEncode({
        'message': 'Client is now offline',
        'timestamp': DateTime.now().toIso8601String(),
      }));
      request.response.close();
    } catch (e) {
      print('❌ [LOCATION ENDPOINT] Error handling simulate offline request: $e');
      request.response.statusCode = 500;
      request.response.write(jsonEncode({
        'error': 'Internal Server Error',
        'message': e.toString(),
      }));
      request.response.close();
    }
  }

  // Handle simulate online requests
  static void _handleSimulateOnlineRequest(HttpRequest request) {
    try {
      print('🔌 [LOCATION ENDPOINT] Simulating online state');
      request.response.statusCode = 200;
      request.response.write(jsonEncode({
        'message': 'Client is now online',
        'timestamp': DateTime.now().toIso8601String(),
      }));
      request.response.close();
    } catch (e) {
      print('❌ [LOCATION ENDPOINT] Error handling simulate online request: $e');
      request.response.statusCode = 500;
      request.response.write(jsonEncode({
        'error': 'Internal Server Error',
        'message': e.toString(),
      }));
      request.response.close();
    }
  }

  // Get current location data
  static LocationData? get currentLocation => _currentLocation;

  // Force location update
  static Future<void> forceLocationUpdate() async {
    await _updateLocation();
  }
}
