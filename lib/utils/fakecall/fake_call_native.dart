// Platform-specific implementation for native fake call (Android/iOS)
// Only imported on Android/iOS
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';

Future<void> showNativeFakeCall(Map<String, dynamic> params) async {
  await FlutterCallkitIncoming.showCallkitIncoming(CallKitParams.fromJson(params));
}
