import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

class LocationService {
  static const String _baseUrl = 'http://budd.systems:9442'; // Backend URL
  static const Duration _timeout = Duration(seconds: 10);

  // Start location sharing session with backend
  static Future<LocationSharingResponse> startLocationSharing({
    required String clientId,
    required String phoneNumber,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      print('🚀 [LOCATION SERVICE] Starting location sharing session');
      print('📱 Client ID: $clientId');
      print('📞 Phone Number: $phoneNumber');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/location/start'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'clientId': clientId,
          'phoneNumber': phoneNumber,
          'metadata': metadata ?? {},
        }),
      ).timeout(_timeout);

      print('📡 Response status: ${response.statusCode}');
      print('📄 Response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 201) {
        print('✅ Location sharing started successfully');
        return LocationSharingResponse.success(
          sessionId: responseData['data']['sessionId'],
          status: responseData['data']['status'],
        );
      } else {
        print('❌ Location sharing failed: ${responseData['message']}');
        return LocationSharingResponse.error(
          code: responseData['code'] ?? 'UNKNOWN_ERROR',
          message: responseData['message'] ?? 'Failed to start location sharing',
        );
      }
    } catch (e) {
      print('❌ Location sharing error: $e');
      return LocationSharingResponse.error(
        code: 'NETWORK_ERROR',
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // Stop location sharing session
  static Future<LocationSharingResponse> stopLocationSharing({
    required String sessionId,
  }) async {
    try {
      print('🛑 [LOCATION SERVICE] Stopping location sharing session: $sessionId');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/location/stop'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'sessionId': sessionId,
        }),
      ).timeout(_timeout);

      print('📡 Stop response status: ${response.statusCode}');
      print('📄 Stop response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ Location sharing stopped successfully');
        return LocationSharingResponse.success(
          sessionId: responseData['data']['sessionId'],
          status: responseData['data']['status'],
        );
      } else {
        print('❌ Stop location sharing failed: ${responseData['message']}');
        return LocationSharingResponse.error(
          code: responseData['code'] ?? 'UNKNOWN_ERROR',
          message: responseData['message'] ?? 'Failed to stop location sharing',
        );
      }
    } catch (e) {
      print('❌ Stop location sharing error: $e');
      return LocationSharingResponse.error(
        code: 'NETWORK_ERROR',
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // Get session details
  static Future<LocationSessionResponse> getSessionDetails({
    required String sessionId,
  }) async {
    try {
      print('📊 [LOCATION SERVICE] Getting session details: $sessionId');

      final response = await http.get(
        Uri.parse('$_baseUrl/api/location/session/$sessionId'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(_timeout);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ Session details retrieved successfully');
        return LocationSessionResponse.success(
          sessionData: responseData['data'],
        );
      } else {
        print('❌ Get session details failed: ${responseData['message']}');
        return LocationSessionResponse.error(
          code: responseData['code'] ?? 'UNKNOWN_ERROR',
          message: responseData['message'] ?? 'Failed to get session details',
        );
      }
    } catch (e) {
      print('❌ Get session details error: $e');
      return LocationSessionResponse.error(
        code: 'NETWORK_ERROR',
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // Get location history
  static Future<LocationHistoryResponse> getLocationHistory({
    required String sessionId,
    int limit = 100,
  }) async {
    try {
      print('📈 [LOCATION SERVICE] Getting location history: $sessionId');

      final response = await http.get(
        Uri.parse('$_baseUrl/api/location/history/$sessionId?limit=$limit'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(_timeout);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ Location history retrieved successfully');
        return LocationHistoryResponse.success(
          history: List<Map<String, dynamic>>.from(responseData['data']['history']),
          totalRecords: responseData['data']['totalRecords'],
        );
      } else {
        print('❌ Get location history failed: ${responseData['message']}');
        return LocationHistoryResponse.error(
          code: responseData['code'] ?? 'UNKNOWN_ERROR',
          message: responseData['message'] ?? 'Failed to get location history',
        );
      }
    } catch (e) {
      print('❌ Get location history error: $e');
      return LocationHistoryResponse.error(
        code: 'NETWORK_ERROR',
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // Get session status
  static Future<LocationSessionResponse> getSessionStatus(String sessionId) async {
    try {
      print('🔍 [LOCATION SERVICE] Getting session status: $sessionId');

      final response = await http.get(
        Uri.parse('$_baseUrl/api/location/session/$sessionId'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(_timeout);

      print('📡 Session status response: ${response.statusCode}');
      print('📄 Session status body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ Session status retrieved successfully');
        return LocationSessionResponse.success(
          sessionData: responseData['data'] ?? {},
        );
      } else {
        print('❌ Failed to get session status: ${responseData['message']}');
        return LocationSessionResponse.error(
          code: responseData['code'] ?? 'UNKNOWN_ERROR',
          message: responseData['message'] ?? 'Failed to get session status',
        );
      }
    } catch (e) {
      print('❌ Session status error: $e');
      return LocationSessionResponse.error(
        code: 'NETWORK_ERROR',
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // Send location update to backend
  static Future<LocationUpdateResponse> sendLocationUpdate({
    required String sessionId,
    required LocationData locationData,
  }) async {
    try {
      print('📍 [LOCATION SERVICE] Sending location update for session: $sessionId');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/location/update'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'sessionId': sessionId,
          'locationData': locationData.toJson(),
        }),
      ).timeout(_timeout);

      print('📡 Update response status: ${response.statusCode}');
      print('📄 Update response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ Location update sent successfully');
        return LocationUpdateResponse.success(
          sessionId: responseData['data']['sessionId'],
          timestamp: responseData['data']['timestamp'],
        );
      } else {
        print('❌ Location update failed: ${responseData['message']}');
        return LocationUpdateResponse.error(
          code: responseData['code'] ?? 'UNKNOWN_ERROR',
          message: responseData['message'] ?? 'Failed to send location update',
        );
      }
    } catch (e) {
      print('❌ Location update error: $e');
      return LocationUpdateResponse.error(
        code: 'NETWORK_ERROR',
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // Get current location using Geolocator
  static Future<LocationData?> getCurrentLocation() async {
    try {
      print('📍 [LOCATION SERVICE] Getting current location');

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('❌ Location services are disabled');
        return null;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('❌ Location permissions are denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('❌ Location permissions are permanently denied');
        return null;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      );

      print('✅ Location obtained: ${position.latitude}, ${position.longitude}');

      return LocationData(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        altitude: position.altitude,
        speed: position.speed,
        heading: position.heading,
        timestamp: DateTime.now().toIso8601String(),
      );
    } catch (e) {
      print('❌ Get current location error: $e');
      return null;
    }
  }

  // Generate unique client ID
  static String generateClientId() {
    return 'client_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (999 * (DateTime.now().microsecond / 1000000))).round()}';
  }
}

// Response classes
class LocationSharingResponse {
  final bool success;
  final String? sessionId;
  final String? status;
  final String? code;
  final String? message;

  LocationSharingResponse._({
    required this.success,
    this.sessionId,
    this.status,
    this.code,
    this.message,
  });

  factory LocationSharingResponse.success({
    required String sessionId,
    required String status,
  }) {
    return LocationSharingResponse._(
      success: true,
      sessionId: sessionId,
      status: status,
    );
  }

  factory LocationSharingResponse.error({
    required String code,
    required String message,
  }) {
    return LocationSharingResponse._(
      success: false,
      code: code,
      message: message,
    );
  }
}

class LocationUpdateResponse {
  final bool success;
  final String? sessionId;
  final String? timestamp;
  final String? code;
  final String? message;

  LocationUpdateResponse._({
    required this.success,
    this.sessionId,
    this.timestamp,
    this.code,
    this.message,
  });

  factory LocationUpdateResponse.success({
    required String sessionId,
    required String timestamp,
  }) {
    return LocationUpdateResponse._(
      success: true,
      sessionId: sessionId,
      timestamp: timestamp,
    );
  }

  factory LocationUpdateResponse.error({
    required String code,
    required String message,
  }) {
    return LocationUpdateResponse._(
      success: false,
      code: code,
      message: message,
    );
  }
}

class LocationSessionResponse {
  final bool success;
  final Map<String, dynamic>? sessionData;
  final String? code;
  final String? message;

  LocationSessionResponse._({
    required this.success,
    this.sessionData,
    this.code,
    this.message,
  });

  factory LocationSessionResponse.success({
    required Map<String, dynamic> sessionData,
  }) {
    return LocationSessionResponse._(
      success: true,
      sessionData: sessionData,
    );
  }

  factory LocationSessionResponse.error({
    required String code,
    required String message,
  }) {
    return LocationSessionResponse._(
      success: false,
      code: code,
      message: message,
    );
  }
}

class LocationHistoryResponse {
  final bool success;
  final List<Map<String, dynamic>>? history;
  final int? totalRecords;
  final String? code;
  final String? message;

  LocationHistoryResponse._({
    required this.success,
    this.history,
    this.totalRecords,
    this.code,
    this.message,
  });

  factory LocationHistoryResponse.success({
    required List<Map<String, dynamic>> history,
    required int totalRecords,
  }) {
    return LocationHistoryResponse._(
      success: true,
      history: history,
      totalRecords: totalRecords,
    );
  }

  factory LocationHistoryResponse.error({
    required String code,
    required String message,
  }) {
    return LocationHistoryResponse._(
      success: false,
      code: code,
      message: message,
    );
  }
}


// Location data model
class LocationData {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double altitude;
  final double speed;
  final double heading;
  final String timestamp;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.altitude,
    required this.speed,
    required this.heading,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'altitude': altitude,
      'speed': speed,
      'heading': heading,
      'timestamp': timestamp,
    };
  }

  factory LocationData.fromJson(Map<String, dynamic> json) {
    return LocationData(
      latitude: json['latitude']?.toDouble() ?? 0.0,
      longitude: json['longitude']?.toDouble() ?? 0.0,
      accuracy: json['accuracy']?.toDouble() ?? 0.0,
      altitude: json['altitude']?.toDouble() ?? 0.0,
      speed: json['speed']?.toDouble() ?? 0.0,
      heading: json['heading']?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] ?? DateTime.now().toIso8601String(),
    );
  }
}
