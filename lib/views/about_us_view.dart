import 'package:flutter/material.dart';

class AboutUsView extends StatelessWidget {
  const AboutUsView({super.key});
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
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF8F5FE8)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('About Us',
            style: TextStyle(
                fontWeight: FontWeight.bold, color: Color(0xFF8F5FE8))),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF8F6FC),
      body: content,
    );
  }
}
