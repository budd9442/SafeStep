import 'package:safestep/services/sos_blocker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:safestep/panic_screen.dart';

class SosNavigationService {
  static const MethodChannel _channel = MethodChannel('com.example.safestep/sos');
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static bool _initialized = false;
  static bool _pendingSosOpen = false;

  static void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
    // In case a request arrived before navigator mounted, try after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryOpenPending());
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'openSosScreen':
        // Block SOS if gesture recording is in progress
        if (!SosBlocker.blockSos) {
          _openSosScreenQueued();
        }
        return null;
      default:
        throw PlatformException(
          code: 'UNIMPLEMENTED',
          message: 'SosNavigationService does not implement ${call.method}',
        );
    }
  }

  static void _openSosScreenQueued() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingSosOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryOpenPending());
      return;
    }
    _pendingSosOpen = false;
    navigator.push(
      MaterialPageRoute(
        builder: (context) => const TenSecondPanicScreen(),
      ),
    );
  }

  static void _tryOpenPending() {
    if (_pendingSosOpen) {
      _openSosScreenQueued();
    }
  }

  static void dispose() {
    // no-op: keeping channel handler for app lifetime
  }
}
