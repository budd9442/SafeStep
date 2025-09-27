import 'dart:async';
import 'package:flutter/material.dart';
import 'package:awesome_ripple_animation/awesome_ripple_animation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:safestep/services/local_session.dart';

class TenSecondPanicScreen extends StatefulWidget {
  const TenSecondPanicScreen({super.key});

  @override
  State<TenSecondPanicScreen> createState() => _TenSecondPanicScreenState();
}

class _TenSecondPanicScreenState extends State<TenSecondPanicScreen> {
  late Timer _timer;
  int _countdown = 10;
  bool _isAlerting = false;
  bool _alertSent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() => _countdown--);
      } else {
        _timer.cancel();
        _sendEmergencyAlert();
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _sendEmergencyAlert() async {
    try {
      setState(() {
        _isAlerting = true;
        _error = null;
      });

      print('🚨 [EMERGENCY] Starting emergency alert process');

      // Get current user info
      final userId = await LocalSession.getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      // Get current location
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      print('📍 [EMERGENCY] Current location: ${position.latitude}, ${position.longitude}');

      // Get user name from Firebase (you might need to adjust this based on your user structure)
      // For now, we'll use a placeholder
      const userName = 'SafeStep User';

      // Send emergency alert to backend
      final response = await http.post(
        Uri.parse('http://budd.systems:9442/api/emergency/alert'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'userId': userId,
          'userName': userName,
          'latitude': position.latitude,
          'longitude': position.longitude,
          'timestamp': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('✅ [EMERGENCY] Alert sent successfully: ${responseData['data']['successCount']} contacts alerted');
        
        setState(() {
          _alertSent = true;
          _isAlerting = false;
        });
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to send emergency alert');
      }
    } catch (e) {
      print('❌ [EMERGENCY] Error sending alert: $e');
      setState(() {
        _error = e.toString();
        _isAlerting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          children: [
            const SizedBox(height: 140),
            // Show different UI based on state
            if (!_isAlerting && !_alertSent && _error == null) ...[
              // Countdown state
              RippleAnimation(
                key: UniqueKey(),
                repeat: true,
                duration: const Duration(milliseconds: 900),
                ripplesCount: 3,
                color: const Color(0xFF8F5FE8),
                minRadius: 100,
                size: const Size(170, 170),
                child: CircleAvatar(
                  radius: 50,
                  backgroundColor: const Color(0xFF8F5FE8),
                  child: Text(
                    '$_countdown',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 80,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 100),
              const Text(
                'KEEP CALM!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                  color: Color(0xFF8F5FE8),
                ),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Within 10 seconds, your close contacts will be alerted of your whereabouts.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                    color: Colors.black,
                  ),
                ),
              ),
            ] else if (_isAlerting) ...[
              // Alerting state
              RippleAnimation(
                key: UniqueKey(),
                repeat: true,
                duration: const Duration(milliseconds: 600),
                ripplesCount: 5,
                color: Colors.red,
                minRadius: 100,
                size: const Size(170, 170),
                child: const CircleAvatar(
                  radius: 50,
                  backgroundColor: Colors.red,
                  child: Icon(
                    Icons.warning,
                    color: Colors.white,
                    size: 60,
                  ),
                ),
              ),
              const SizedBox(height: 100),
              const Text(
                'ALERTING CLOSE CONTACTS',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                  color: Colors.red,
                ),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Sending emergency alerts to your close contacts with your location...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                    color: Colors.black,
                  ),
                ),
              ),
            ] else if (_alertSent) ...[
              // Success state
              const CircleAvatar(
                radius: 50,
                backgroundColor: Colors.green,
                child: Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 60,
                ),
              ),
              const SizedBox(height: 100),
              const Text(
                'ALERT SENT SUCCESSFULLY!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Your close contacts have been notified with your location. Help is on the way!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                    color: Colors.black,
                  ),
                ),
              ),
            ] else if (_error != null) ...[
              // Error state
              const CircleAvatar(
                radius: 50,
                backgroundColor: Colors.orange,
                child: Icon(
                  Icons.error,
                  color: Colors.white,
                  size: 60,
                ),
              ),
              const SizedBox(height: 100),
              const Text(
                'ALERT FAILED',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Failed to send alert: $_error',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Poppins',
                    color: Colors.black,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 60),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Press the button below to stop SOS alert.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Poppins',
                ),
              ),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.only(bottom: 50),
              child: ElevatedButton(
                onPressed: () {
                  _timer.cancel();
                  Navigator.of(context).pop();
                },
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF8F5FE8),
                  minimumSize: const Size(200, 70),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(50),
                  ),
                ),
                child: const Text(
                  'STOP SENDING SOS ALERT',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Poppins',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}








