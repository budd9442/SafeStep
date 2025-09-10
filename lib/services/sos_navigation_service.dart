import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:safestep/panic_screendart.dart';

class SosNavigationService {
  static const MethodChannel _channel = MethodChannel('com.example.safestep/sos');
  static BuildContext? _context;
  
  static void initialize(BuildContext context) {
    _context = context;
    _channel.setMethodCallHandler(_handleMethodCall);
  }
  
  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'openSosScreen':
        await _openSosScreen();
        break;
      default:
        throw PlatformException(
          code: 'UNIMPLEMENTED',
          message: 'SosNavigationService does not implement ${call.method}',
        );
    }
  }
  
  static Future<void> _openSosScreen() async {
    if (_context != null) {
      // Navigate to the SOS screen
      Navigator.of(_context!).push(
        MaterialPageRoute(
          builder: (context) => const TenSecondPanicScreen(),
        ),
      );
    }
  }
  
  static void dispose() {
    _context = null;
  }
}
