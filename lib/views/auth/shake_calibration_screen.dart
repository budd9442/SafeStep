import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/local_session.dart';
import '../onboarding_screens.dart';
import '../../services/sos_blocker.dart';

class ShakeCalibrationScreen extends StatefulWidget {
  const ShakeCalibrationScreen({super.key});

  @override
  State<ShakeCalibrationScreen> createState() => _ShakeCalibrationScreenState();
}

class _ShakeCalibrationScreenState extends State<ShakeCalibrationScreen> {
  bool _isCalibrating = false;
  bool _calibrationComplete = false;
  double? _maxGestureValue;
  String? _error;
  int _countdown = 7;
  double _calibrationProgress = 0.0;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),
              
              // Header
              const Text(
                'Shake Detection Calibration',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF232946),
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 12),
              
              const Text(
                'We need to calibrate your shake detection to ensure it works perfectly for emergency situations.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF777B84),
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 32),
              
              // Calibration status
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    if (!_calibrationComplete) ...[
                      Icon(
                        _isCalibrating ? Icons.vibration : Icons.phone_android,
                        size: 56,
                        color: _isCalibrating ? Colors.orange : const Color(0xFF8F5FE8),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isCalibrating ? 'Recording...' : 'Ready to Calibrate',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF232946),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isCalibrating 
                            ? 'Shake your phone as hard as you can!'
                            : 'Tap the button below to start calibration',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF777B84),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_isCalibrating) ...[
                        const SizedBox(height: 20),
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                strokeWidth: 6,
                                value: _calibrationProgress,
                                backgroundColor: Colors.grey.shade200,
                                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8F5FE8)),
                              ),
                              Text(
                                '$_countdown',
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF8F5FE8),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Recording your shake pattern...",
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF777B84),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ] else ...[
                      const Icon(
                        Icons.check_circle,
                        size: 56,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Calibration Complete!',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF232946),
                        ),
                      ),
                      const SizedBox(height: 8),
                       const Text(
                         'Shake detection is now calibrated and ready!',
                         style: TextStyle(
                           fontSize: 13,
                           color: Color(0xFF777B84),
                         ),
                       ),
                    ],
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Action button
              if (!_calibrationComplete) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isCalibrating ? null : _startCalibration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8F5FE8),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _isCalibrating ? 'Calibrating...' : 'Start Calibration',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _completeSetup,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Complete Setup',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
              
              const SizedBox(height: 16),
              
              // Error message
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade600, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 16),
              
              // Skip option (for testing)
              TextButton(
                onPressed: _skipCalibration,
                child: const Text(
                  'Skip for now (not recommended)',
                  style: TextStyle(
                    color: Color(0xFF777B84),
                    fontSize: 13,
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startCalibration() async {
    setState(() {
      _isCalibrating = true;
      _error = null;
    });

    try {
      // Start calibration process directly
      await _performCalibration();

    } catch (e) {
      setState(() {
        _error = "Calibration failed: $e";
        _isCalibrating = false;
      });
    }
  }

  Future<void> _performCalibration() async {
    SosBlocker.blockSos = true;
    
    // Reset countdown and progress
    setState(() {
      _isCalibrating = true;
      _countdown = 7;
      _calibrationProgress = 0.0;
    });

    // Start countdown timer
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() {
          _countdown--;
          _calibrationProgress = (7 - _countdown) / 7;
        });
      } else {
        timer.cancel();
        setState(() {
          _countdown = 0;
          _calibrationProgress = 1.0;
        });
      }
    });

    // Platform call to record shake gesture (native handles the 7-second timing)
    double? maxDelta;
    try {
      final platform = MethodChannel('com.example.safestep/shake_gesture');
      final result = await platform.invokeMethod('recordShakeGesture');
      
      if (result is double) {
        maxDelta = result;
      } else if (result is int) {
        maxDelta = result.toDouble();
      }
      
      print('🎯 [SHAKE CALIBRATION] Recorded max gesture value: $maxDelta');
      
    } on PlatformException catch (e) {
      print('❌ [SHAKE CALIBRATION] Platform error: ${e.message}');
      setState(() {
        _error = "Failed to record shake: ${e.message}";
        _isCalibrating = false;
      });
      SosBlocker.blockSos = false;
      return;
    } catch (e) {
      print('❌ [SHAKE CALIBRATION] Error: $e');
      setState(() {
        _error = "Calibration failed: $e";
        _isCalibrating = false;
      });
      SosBlocker.blockSos = false;
      return;
    } finally {
      SosBlocker.blockSos = false;
    }

    // Update state with calibration result
    setState(() {
      _maxGestureValue = maxDelta;
      _calibrationComplete = true;
      _isCalibrating = false;
    });
  }

  Future<void> _completeSetup() async {
    try {
      // Get current user ID
      final userId = await LocalSession.getCurrentUserId();
      if (userId == null) {
        throw Exception('No user ID found');
      }

      // Update user document with calibration data
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'gestureRecorded': true,
        'maxGestureValue': _maxGestureValue,
        'profileComplete': true,
      });

      // Save max gesture value to Android SharedPreferences for service use
      if (_maxGestureValue != null) {
        try {
          const platform = MethodChannel('com.example.safestep/prefs');
          await platform.invokeMethod('saveUserMaxGesture', {
            'maxGestureValue': _maxGestureValue,
          });
          print('✅ [SHAKE CALIBRATION] Saved gesture value to SharedPreferences: $_maxGestureValue');
        } catch (e) {
          print('⚠️ [SHAKE CALIBRATION] Failed to save to SharedPreferences: $e');
          // Continue anyway, not critical
        }
      }

      // Start shake detection service
      try {
        const platform = MethodChannel('com.example.safestep/shake_gesture');
        await platform.invokeMethod('startShakeDetection');
        print('✅ [SHAKE CALIBRATION] Started shake detection service');
      } catch (e) {
        print('⚠️ [SHAKE CALIBRATION] Failed to start shake detection service: $e');
        // Continue anyway
      }

      // Navigate to onboarding screen
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => OnboardingScreen(phoneNumber: userId)),
          (route) => false,
        );
      }

    } catch (e) {
      setState(() {
        _error = "Failed to complete setup: $e";
      });
    }
  }

  Future<void> _skipCalibration() async {
    // Complete setup without calibration
    await _completeSetup();
  }
}
