import 'package:flutter/material.dart';

class DebugScreen extends StatelessWidget {
  final bool internal;
  const DebugScreen({super.key, this.internal = false});
  @override
  Widget build(BuildContext context) {
    final content = const Center(
      child: Text('Debug tools and logs will appear here.'),
    );
    if (internal) return content;
    return Scaffold(appBar: AppBar(title: const Text('Debug')), body: content);
  }
}
