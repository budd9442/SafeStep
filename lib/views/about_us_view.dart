import 'package:flutter/material.dart';

class AboutUsView extends StatelessWidget {
  final bool internal;
  const AboutUsView({super.key, this.internal = false});
  @override
  Widget build(BuildContext context) {
    final content = const Center(
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Text(
          'SafeStep is dedicated to empowering women with safety tools, psychological support, and community features. Our mission is to make every step safer.',
          style: TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
    if (internal) return content;
    return Scaffold(appBar: AppBar(title: const Text('About Us')), body: content);
  }
}
