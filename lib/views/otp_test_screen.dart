import 'package:flutter/material.dart';
import '../../services/otp_service.dart';

class OTPTestScreen extends StatefulWidget {
  const OTPTestScreen({super.key});

  @override
  State<OTPTestScreen> createState() => _OTPTestScreenState();
}

class _OTPTestScreenState extends State<OTPTestScreen> {
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    // Pre-fill with the reference from your logs
    _referenceController.text = 'REF_1758517915783_u3u58viyn';
    // Pre-fill with the OTP you received
    _otpController.text = '229904';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OTP Test'),
        backgroundColor: const Color(0xFF7B3FA0),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Test OTP Verification',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            
            TextField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Reference ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _otpController,
              decoration: const InputDecoration(
                labelText: 'OTP Code',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              maxLength: 6,
            ),
            const SizedBox(height: 24),
            
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
            ],
            
            if (_success != null) ...[
              Text(_success!, style: const TextStyle(color: Colors.green)),
              const SizedBox(height: 16),
            ],
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _testOTP,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B3FA0),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Test OTP Verification',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _testUserCheck,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Test User Check',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _testOTP() async {
    if (_referenceController.text.trim().isEmpty || _otpController.text.trim().isEmpty) {
      setState(() { _error = 'Please fill in all fields'; });
      return;
    }

    setState(() { 
      _loading = true; 
      _error = null; 
      _success = null; 
    });

    try {
      final response = await OTPService.verifyOTP(
        reference: _referenceController.text.trim(),
        otp: _otpController.text.trim(),
      );

      if (response.success) {
        setState(() {
          _success = 'OTP verification successful!\n'
                    'Phone: ${response.phoneNumber}\n'
                    'Verified at: ${response.verifiedAt}\n'
                    'Status: ${response.subscriptionStatus}';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'OTP verification failed: ${response.message}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to verify OTP: ${e.toString()}';
        _loading = false;
      });
    }
  }

  Future<void> _testUserCheck() async {
    setState(() { 
      _loading = true; 
      _error = null; 
      _success = null; 
    });

    try {
      final response = await OTPService.checkUserExists('tel:94714555151');

      if (response.success) {
        setState(() {
          _success = 'User check successful!\n'
                    'User exists: ${response.exists}\n'
                    'User data: ${response.userData}';
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'User check failed: ${response.message}';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to check user: ${e.toString()}';
        _loading = false;
      });
    }
  }
}

