import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class OTPService {
  static const String _baseUrl = 'http://budd.systems:9442'; // Change this to your actual backend URLtems
  static const Duration _timeout = Duration(seconds: 10);

  // Format phone number for Sri Lankan numbers
  static String _formatPhoneNumber(String phone) {
    // Remove all non-digit characters
    String digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    
    // Handle Sri Lankan mobile numbers
    if (digits.length == 9 && digits.startsWith('7')) {
      return 'tel:94$digits';
    } else if (digits.length == 12 && digits.startsWith('947')) {
      return 'tel:$digits';
    } else if (digits.length == 10 && digits.startsWith('0')) {
      // Handle numbers starting with 0
      return 'tel:94${digits.substring(1)}';
    }
    
    // Return as-is if already formatted
    return phone.startsWith('tel:') ? phone : 'tel:$digits';
  }

  // Request OTP from custom backend
  static Future<OTPResponse> requestOTP({
    required String phoneNumber,
    Map<String, dynamic>? applicationMetaData,
  }) async {
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries) {
      try {
        final formattedPhone = _formatPhoneNumber(phoneNumber);
        
        print('🔄 Attempting OTP request (attempt ${retryCount + 1}/$maxRetries)');
        print('📱 Phone: $formattedPhone');
        
        final response = await http.post(
          Uri.parse('$_baseUrl/api/otp/request'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Connection': 'keep-alive',
          },
          body: jsonEncode({
            'phoneNumber': formattedPhone,
            'applicationMetaData': applicationMetaData ?? {
              'client': 'MOBILEAPP',
              'device': 'Flutter App',
              'os': defaultTargetPlatform.name,
              'appCode': 'SafeStep'
            }
          }),
        ).timeout(_timeout);

        print('📡 Response status: ${response.statusCode}');
        print('📄 Response body: ${response.body}');

        final responseData = jsonDecode(response.body);

        if (response.statusCode == 200) {
          print('✅ OTP request successful');
          return OTPResponse.success(
            reference: responseData['reference'],
            phoneNumber: responseData['phoneNumber'],
            expiresIn: responseData['expiresIn'],
          );
        } else {
          print('❌ OTP request failed: ${responseData['message']}');
          return OTPResponse.error(
            code: responseData['code'] ?? 'UNKNOWN_ERROR',
            message: responseData['message'] ?? responseData['error'] ?? 'Failed to send OTP',
          );
        }
      } catch (e) {
        retryCount++;
        print('❌ OTP request error (attempt $retryCount): $e');
        
        if (retryCount >= maxRetries) {
          print('❌ Max retries reached, giving up');
          return OTPResponse.error(
            code: 'NETWORK_ERROR',
            message: 'Network error after $maxRetries attempts: ${e.toString()}',
          );
        }
        
        // Wait before retrying (exponential backoff)
        await Future.delayed(Duration(seconds: retryCount * 2));
      }
    }
    
    return OTPResponse.error(
      code: 'UNKNOWN_ERROR',
      message: 'Unexpected error occurred',
    );
  }

  // Verify OTP with custom backend
  static Future<OTPVerificationResponse> verifyOTP({
    required String reference,
    required String otp,
  }) async {
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries) {
      try {
        print('🔄 Attempting OTP verification (attempt ${retryCount + 1}/$maxRetries)');
        print('🔑 Reference: $reference');
        print('🔢 OTP: $otp');
        
        final response = await http.post(
          Uri.parse('$_baseUrl/api/otp/verify'),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'Connection': 'keep-alive',
          },
          body: jsonEncode({
            'reference': reference,
            'otp': otp,
          }),
        ).timeout(_timeout);

        print('📡 Verification response status: ${response.statusCode}');
        print('📄 Verification response body: ${response.body}');

        final responseData = jsonDecode(response.body);

        if (response.statusCode == 200) {
          print('✅ OTP verification successful');
          return OTPVerificationResponse.success(
            phoneNumber: responseData['phoneNumber'],
            verifiedAt: responseData['verifiedAt'],
            subscriptionStatus: responseData['subscriptionStatus'],
          );
        } else {
          print('❌ OTP verification failed: ${responseData['message']}');
          return OTPVerificationResponse.error(
            code: responseData['code'] ?? 'UNKNOWN_ERROR',
            message: responseData['message'] ?? responseData['error'] ?? 'Failed to verify OTP',
            attemptsRemaining: responseData['attemptsRemaining'],
          );
        }
      } catch (e) {
        retryCount++;
        print('❌ OTP verification error (attempt $retryCount): $e');
        
        if (retryCount >= maxRetries) {
          print('❌ Max retries reached for verification, giving up');
          return OTPVerificationResponse.error(
            code: 'NETWORK_ERROR',
            message: 'Network error after $maxRetries attempts: ${e.toString()}',
          );
        }
        
        // Wait before retrying (exponential backoff)
        await Future.delayed(Duration(seconds: retryCount * 2));
      }
    }
    
    return OTPVerificationResponse.error(
      code: 'UNKNOWN_ERROR',
      message: 'Unexpected error occurred during verification',
    );
  }

  // Check if user exists by phone number
  static Future<UserExistenceResponse> checkUserExists(String phoneNumber) async {
    try {
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      print('🔍 Checking user existence for: $phoneNumber (formatted: $formattedPhone)');
      
      final response = await http.get(
        Uri.parse('$_baseUrl/api/user/check/$formattedPhone'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(_timeout);

      print('📡 User check response status: ${response.statusCode}');
      print('📄 User check response body: ${response.body}');

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        print('✅ User check successful, exists: ${responseData['exists']}');
        return UserExistenceResponse.success(
          exists: responseData['exists'] ?? false,
          userData: responseData['userData'],
        );
      } else {
        print('❌ User check failed with status: ${response.statusCode}');
        return UserExistenceResponse.error(
          code: responseData['code'] ?? 'UNKNOWN_ERROR',
          message: responseData['message'] ?? responseData['error'] ?? 'Failed to check user',
        );
      }
    } catch (e) {
      print('❌ User check network error: $e');
      return UserExistenceResponse.error(
        code: 'NETWORK_ERROR',
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // Check OTP status
  static Future<OTPStatusResponse> checkOTPStatus(String reference) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/otp/status/$reference'),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(_timeout);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return OTPStatusResponse.success(
          reference: responseData['reference'],
          status: responseData['status'],
          phoneNumber: responseData['phoneNumber'],
          attempts: responseData['attempts'],
          maxAttempts: responseData['maxAttempts'],
          createdAt: responseData['createdAt'],
          expiresAt: responseData['expiresAt'],
          isExpired: responseData['isExpired'],
        );
      } else {
        return OTPStatusResponse.error(
          code: responseData['code'] ?? 'UNKNOWN_ERROR',
          message: responseData['message'] ?? responseData['error'] ?? 'Failed to check status',
        );
      }
    } catch (e) {
      return OTPStatusResponse.error(
        code: 'NETWORK_ERROR',
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  // Register client mapping (for development/testing)
  static Future<ClientRegistrationResponse> registerClient({
    required String phoneNumber,
    required String clientId,
    Map<String, dynamic>? clientInfo,
  }) async {
    try {
      final formattedPhone = _formatPhoneNumber(phoneNumber);
      
      final response = await http.post(
        Uri.parse('$_baseUrl/api/otp/register-client'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'phoneNumber': formattedPhone,
          'clientId': clientId,
          'clientInfo': clientInfo ?? {},
        }),
      ).timeout(_timeout);

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200) {
        return ClientRegistrationResponse.success(
          phoneNumber: responseData['phoneNumber'],
          clientId: responseData['clientId'],
          action: responseData['action'],
        );
      } else {
        return ClientRegistrationResponse.error(
          code: responseData['code'] ?? 'UNKNOWN_ERROR',
          message: responseData['message'] ?? responseData['error'] ?? 'Failed to register client',
        );
      }
    } catch (e) {
      return ClientRegistrationResponse.error(
        code: 'NETWORK_ERROR',
        message: 'Network error: ${e.toString()}',
      );
    }
  }
}

// Response classes
class OTPResponse {
  final bool success;
  final String? reference;
  final String? phoneNumber;
  final int? expiresIn;
  final String? code;
  final String? message;

  OTPResponse._({
    required this.success,
    this.reference,
    this.phoneNumber,
    this.expiresIn,
    this.code,
    this.message,
  });

  factory OTPResponse.success({
    required String reference,
    required String phoneNumber,
    required int expiresIn,
  }) {
    return OTPResponse._(
      success: true,
      reference: reference,
      phoneNumber: phoneNumber,
      expiresIn: expiresIn,
    );
  }

  factory OTPResponse.error({
    required String code,
    required String message,
  }) {
    return OTPResponse._(
      success: false,
      code: code,
      message: message,
    );
  }
}

class OTPVerificationResponse {
  final bool success;
  final String? phoneNumber;
  final String? verifiedAt;
  final String? subscriptionStatus;
  final String? code;
  final String? message;
  final int? attemptsRemaining;

  OTPVerificationResponse._({
    required this.success,
    this.phoneNumber,
    this.verifiedAt,
    this.subscriptionStatus,
    this.code,
    this.message,
    this.attemptsRemaining,
  });

  factory OTPVerificationResponse.success({
    required String phoneNumber,
    required String verifiedAt,
    required String subscriptionStatus,
  }) {
    return OTPVerificationResponse._(
      success: true,
      phoneNumber: phoneNumber,
      verifiedAt: verifiedAt,
      subscriptionStatus: subscriptionStatus,
    );
  }

  factory OTPVerificationResponse.error({
    required String code,
    required String message,
    int? attemptsRemaining,
  }) {
    return OTPVerificationResponse._(
      success: false,
      code: code,
      message: message,
      attemptsRemaining: attemptsRemaining,
    );
  }
}

class OTPStatusResponse {
  final bool success;
  final String? reference;
  final String? status;
  final String? phoneNumber;
  final int? attempts;
  final int? maxAttempts;
  final String? createdAt;
  final String? expiresAt;
  final bool? isExpired;
  final String? code;
  final String? message;

  OTPStatusResponse._({
    required this.success,
    this.reference,
    this.status,
    this.phoneNumber,
    this.attempts,
    this.maxAttempts,
    this.createdAt,
    this.expiresAt,
    this.isExpired,
    this.code,
    this.message,
  });

  factory OTPStatusResponse.success({
    required String reference,
    required String status,
    required String phoneNumber,
    required int attempts,
    required int maxAttempts,
    required String createdAt,
    required String expiresAt,
    required bool isExpired,
  }) {
    return OTPStatusResponse._(
      success: true,
      reference: reference,
      status: status,
      phoneNumber: phoneNumber,
      attempts: attempts,
      maxAttempts: maxAttempts,
      createdAt: createdAt,
      expiresAt: expiresAt,
      isExpired: isExpired,
    );
  }

  factory OTPStatusResponse.error({
    required String code,
    required String message,
  }) {
    return OTPStatusResponse._(
      success: false,
      code: code,
      message: message,
    );
  }
}

class ClientRegistrationResponse {
  final bool success;
  final String? phoneNumber;
  final String? clientId;
  final String? action;
  final String? code;
  final String? message;

  ClientRegistrationResponse._({
    required this.success,
    this.phoneNumber,
    this.clientId,
    this.action,
    this.code,
    this.message,
  });

  factory ClientRegistrationResponse.success({
    required String phoneNumber,
    required String clientId,
    required String action,
  }) {
    return ClientRegistrationResponse._(
      success: true,
      phoneNumber: phoneNumber,
      clientId: clientId,
      action: action,
    );
  }

  factory ClientRegistrationResponse.error({
    required String code,
    required String message,
  }) {
    return ClientRegistrationResponse._(
      success: false,
      code: code,
      message: message,
    );
  }
}

class UserExistenceResponse {
  final bool success;
  final bool? exists;
  final Map<String, dynamic>? userData;
  final String? code;
  final String? message;

  UserExistenceResponse._({
    required this.success,
    this.exists,
    this.userData,
    this.code,
    this.message,
  });

  factory UserExistenceResponse.success({
    required bool exists,
    Map<String, dynamic>? userData,
  }) {
    return UserExistenceResponse._(
      success: true,
      exists: exists,
      userData: userData,
    );
  }

  factory UserExistenceResponse.error({
    required String code,
    required String message,
  }) {
    return UserExistenceResponse._(
      success: false,
      code: code,
      message: message,
    );
  }
}
