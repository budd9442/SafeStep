import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/local_session.dart';
import 'shake_calibration_screen.dart';

class UserDetailsFormScreen extends StatefulWidget {
  final String phoneNumber;
  final VoidCallback? onComplete;

  const UserDetailsFormScreen({
    super.key,
    required this.phoneNumber,
    this.onComplete,
  });

  @override
  State<UserDetailsFormScreen> createState() => _UserDetailsFormScreenState();
}

class _UserDetailsFormScreenState extends State<UserDetailsFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  DateTime? _selectedDate;
  bool _loading = false;
  String? _error;

  // Gesture recording removed - will be handled in separate calibration screen

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFF7B3FA0).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(40),
                        ),
                        child: const Icon(Icons.person_add, size: 40, color: Color(0xFF7B3FA0)),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Complete Your Profile',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF7B3FA0),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We need a few more details to get you started',
                        style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Phone number display
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.phone, color: Colors.grey.shade600),
                      const SizedBox(width: 12),
                      Text(
                        'Phone: ${widget.phoneNumber}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Verified',
                          style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Name field
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name *',
                    hintText: 'Enter your full name',
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Name is required';
                    if (value.trim().length < 2) return 'Name must be at least 2 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Email field
                TextFormField(
                  controller: _emailController,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    hintText: 'Enter your email (optional)',
                    prefixIcon: const Icon(Icons.email),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value != null && value.isNotEmpty) {
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                        return 'Please enter a valid email address';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // DOB field
                TextFormField(
                  controller: _dobController,
                  decoration: InputDecoration(
                    labelText: 'Date of Birth',
                    hintText: 'Select your date of birth (optional)',
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(icon: const Icon(Icons.calendar_month), onPressed: _selectDate),
                  ),
                  readOnly: true,
                  onTap: _selectDate,
                ),
                const SizedBox(height: 24),
                // Gesture recording removed - will be handled in separate calibration screen
                const SizedBox(height: 32),
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
                        Icon(Icons.error_outline, color: Colors.red.shade600, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_error!, style: TextStyle(color: Colors.red.shade700))),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _completeRegistration,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7B3FA0),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _loading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text(
                            'Save Information',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _dobController.text = '${picked.day}/${picked.month}/${picked.year}';
      });
    }
  }

  // Gesture recording method removed - will be handled in separate calibration screen

  Future<void> _completeRegistration() async {
    if (!_formKey.currentState!.validate()) return;
    // Gesture recording validation removed - will be handled in separate calibration screen

    setState(() { _loading = true; _error = null; });

    try {
      final userData = {
        'phoneNumber': widget.phoneNumber,
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
        'dateOfBirth': _selectedDate != null ? Timestamp.fromDate(_selectedDate!) : null,
        'gestureRecorded': false, // Will be set to true after calibration
        'maxGestureValue': null, // Will be set after calibration
        'createdAt': FieldValue.serverTimestamp(),
      };
      userData.removeWhere((key, value) => value == null);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.phoneNumber)
          .set(userData, SetOptions(merge: true));

      // Create local session for new user
      await LocalSession.setCurrentUserId(widget.phoneNumber);

      // Gesture calibration will be handled in separate screen

      widget.onComplete?.call();
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ShakeCalibrationScreen()), (_) => false);
    } catch (e) {
      setState(() { _error = "Failed to save user info: $e"; });
    } finally {
      setState(() { _loading = false; });
    }
  }
}
