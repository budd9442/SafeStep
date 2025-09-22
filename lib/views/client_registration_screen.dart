import 'package:flutter/material.dart';
import '../services/otp_service.dart';

class ClientRegistrationScreen extends StatefulWidget {
  const ClientRegistrationScreen({super.key});

  @override
  State<ClientRegistrationScreen> createState() => _ClientRegistrationScreenState();
}

class _ClientRegistrationScreenState extends State<ClientRegistrationScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _clientIdController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Client Registration'),
        backgroundColor: const Color(0xFF7B3FA0),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Register Phone Number with Client ID',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                hintText: '+94 77 123 4567',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _clientIdController,
              decoration: const InputDecoration(
                labelText: 'Client ID',
                hintText: 'tel:94771234567',
                prefixIcon: Icon(Icons.person),
                border: OutlineInputBorder(),
              ),
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
                onPressed: _loading ? null : _registerClient,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B3FA0),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Register Client',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Note: This is for development/testing purposes only.\n'
              'In production, client IDs should be managed by your backend system.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _registerClient() async {
    if (_phoneController.text.trim().isEmpty || _clientIdController.text.trim().isEmpty) {
      setState(() { _error = 'Please fill in all fields'; });
      return;
    }

    setState(() { 
      _loading = true; 
      _error = null; 
      _success = null; 
    });

    try {
      final response = await OTPService.registerClient(
        phoneNumber: _phoneController.text.trim(),
        clientId: _clientIdController.text.trim(),
        clientInfo: {
          'registeredAt': DateTime.now().toIso8601String(),
          'platform': 'Flutter',
        },
      );

      if (response.success) {
        setState(() {
          _success = 'Client registered successfully!\n'
                    'Phone: ${response.phoneNumber}\n'
                    'Client ID: ${response.clientId}\n'
                    'Action: ${response.action}';
          _loading = false;
        });
        _phoneController.clear();
        _clientIdController.clear();
      } else {
        setState(() {
          _error = response.message;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to register client: ${e.toString()}';
        _loading = false;
      });
    }
  }
}
