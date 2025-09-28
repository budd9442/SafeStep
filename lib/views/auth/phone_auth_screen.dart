import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:safestep/home_screen.dart';
import 'package:safestep/views/auth/user_details_form_screen.dart';
import '../../services/otp_service.dart';
import '../../services/local_session.dart';


class PhoneAuthScreen extends StatefulWidget {
  final VoidCallback? onAuthSuccess;
  const PhoneAuthScreen({super.key, this.onAuthSuccess});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  bool _loading = false;
  bool _otpSent = false;
  String? _otpReference;
  String? _error;

  String _formatPhoneNumber(String phone) {
    // Remove all non-digit characters
    String digits = phone.replaceAll(RegExp(r'[^\d]'), '');
    
    // Handle Sri Lankan mobile numbers
    if (digits.length == 9 && digits.startsWith('7')) {
      return '+94$digits';
    } else if (digits.length == 12 && digits.startsWith('947')) {
      return '+$digits';
    } else if (digits.length == 10 && digits.startsWith('0')) {
      // Handle numbers starting with 0
      return '+94${digits.substring(1)}';
    }
    return phone; // Return as-is if already formatted
  }

  Future<void> _sendOTP() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    
    try {
      final phoneNumber = _formatPhoneNumber(_phoneController.text.trim());
      
      // Use custom backend OTP service
      final otpResponse = await OTPService.requestOTP(
        phoneNumber: phoneNumber,
        applicationMetaData: {
          'client': 'MOBILEAPP',
          'device': 'Flutter App',
          'os': 'Android/iOS',
          'appCode': 'SafeStep'
        },
      );
      
      if (otpResponse.success) {
        setState(() {
          _otpReference = otpResponse.reference;
          _otpSent = true;
          _loading = false;
        });
      } else {
        setState(() {
          _error = otpResponse.message;
          _loading = false;
        });
      }
    } catch (e) {
      setState(() { 
        _error = 'Failed to send OTP: ${e.toString()}';
        _loading = false;
      });
    }
  }

  // Future<void> _verifyOTP() async {
  //   if (_otpReference == null) return;
    
  //   setState(() { _loading = true; _error = null; });
    
  //   try {
  //     // Use custom backend OTP verification
  //     final verifyResponse = await OTPService.verifyOTP(
  //       reference: _otpReference!,
  //       otp: _otpController.text.trim(),
  //     );
      
  //     if (verifyResponse.success) {
  //       final phoneNumber = verifyResponse.phoneNumber!;
  //       print('✅ OTP verified successfully for: $phoneNumber');
        
  //       // Check if user exists
  //       print('🔍 Checking if user exists...');
  //       final userExistsResponse = await OTPService.checkUserExists(phoneNumber);
  //       print('📋 User exists response: ${userExistsResponse.success}, exists: ${userExistsResponse.exists}');
        
  //     //   if (userExistsResponse.success && userExistsResponse.exists == true) {
  //     //     // User exists - log them in
  //     //     print('👤 User exists, logging in with data: ${userExistsResponse.userData}');
  //     //     await _loginExistingUser(phoneNumber, userExistsResponse.userData);

  //     //     if (!mounted) return;

  //     //     // Fire the callback so AuthGate can rebuild
  //     //     print('🔄 Calling onAuthSuccess for existing user');
  //     //     widget.onAuthSuccess?.call();
  //     //     print('🔄 onAuthSuccess called for existing user');

  //     //     // Stop loading and navigate directly as a fallback
  //     //     setState(() => _loading = false);
  //     //     print('🔄 Navigating directly to home screen for existing user');
  //     //     Navigator.of(context).pushAndRemoveUntil(
  //     //       MaterialPageRoute(builder: (_) => const HomeScreen()),
  //     //       (route) => false,
  //     //     );
  //     //   } else {
  //     //     // User doesn't exist - show details form
  //     //     print('👤 User does not exist, showing registration form');
  //     //     if (mounted) {
  //     //       Navigator.pushReplacement(
  //     //         context,
  //     //         MaterialPageRoute(
  //     //           builder: (context) => UserDetailsFormScreen(
  //     //             phoneNumber: phoneNumber,
  //     //             onComplete: () {
  //     //               if (mounted) {
  //     //                 print('🔄 UserDetailsFormScreen onComplete called');
  //     //                 widget.onAuthSuccess?.call();
  //     //                 print('🔄 onAuthSuccess callback called');
  //     //               }
  //     //             },
  //     //           ),
  //     //         ),
  //     //       );
  //     //     }
  //     //   }
  //     // } 
  //     if (userExistsResponse.success) {
  //       print('👤 Showing user details screen (new or existing user)');
  //       if (mounted) {
  //         Navigator.pushReplacement(
  //           context,
  //           MaterialPageRoute(
  //             builder: (context) => UserDetailsFormScreen(
  //               phoneNumber: phoneNumber,
  //               onComplete: () {
  //                 if (mounted) {
  //                   print('🔄 UserDetailsFormScreen onComplete called');
  //                   widget.onAuthSuccess?.call();
  //                   print('🔄 onAuthSuccess callback called');
  //                 }
  //               },
  //             ),
  //           ),
  //         );
  //       }
  //     } else {
  //         // User doesn't exist - show details form
  //         print('👤 User does not exist, showing registration form');
  //         if (mounted) {
  //           Navigator.pushReplacement(
  //             context,
  //             MaterialPageRoute(
  //               builder: (context) => UserDetailsFormScreen(
  //                 phoneNumber: phoneNumber,
  //                 onComplete: () {
  //                   if (mounted) {
  //                     print('🔄 UserDetailsFormScreen onComplete called');
  //                     widget.onAuthSuccess?.call();
  //                     print('🔄 onAuthSuccess callback called');
  //                   }
  //                 },
  //               ),
  //             ),
  //           );
  //         }
  //       }
  //     } 
  //     else {
  //       if (mounted) {
  //         setState(() { 
  //           _error = verifyResponse.message;
  //           _loading = false;
  //         });
  //       }
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       setState(() { 
  //         _error = 'Failed to verify OTP: ${e.toString()}';
  //         _loading = false;
  //       });
  //     }
  //   }
  // }
  Future<void> _verifyOTP() async {
  if (_otpReference == null) return;

  setState(() {
    _loading = true;
    _error = null;
  });

  try {
    final verifyResponse = await OTPService.verifyOTP(
      reference: _otpReference!,
      otp: _otpController.text.trim(),
    );

    if (verifyResponse.success) {
      final phoneNumber = verifyResponse.phoneNumber!;
      print('🔍 [AUTH] OTP verified successfully for phone: $phoneNumber');

      print('🔍 [AUTH] Checking if user exists for phone: $phoneNumber');
      final userExistsResponse = await OTPService.checkUserExists(phoneNumber);
      print('🔍 [AUTH] User exists check result: success=${userExistsResponse.success}, userData=${userExistsResponse.userData}');

      if (userExistsResponse.success) {
        // User exists - check if profile is complete
        final userData = userExistsResponse.userData;
        final profileComplete = userData?['profileComplete'] ?? false;
        
        print('✅ [AUTH] User exists, profileComplete: $profileComplete');
        
        if (profileComplete) {
          // Profile is complete - create session and navigate to home
          print('✅ [AUTH] Profile is complete, creating session and navigating to home');
          await _createCustomUserSession(phoneNumber, userData);
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => HomeScreen(),
              ),
            );
          }
        } else {
          // Profile is incomplete - navigate to profile completion
          print('👤 [AUTH] Profile is incomplete, navigating to profile completion');
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => UserDetailsFormScreen(
                  phoneNumber: phoneNumber,
                  onComplete: () {
                    if (mounted) {
                      widget.onAuthSuccess?.call();
                    }
                  },
                ),
              ),
            );
          }
        }
      } else {
        // User doesn't exist - navigate to details form
        print('👤 [AUTH] User does not exist, navigating to user details form');
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => UserDetailsFormScreen(
                phoneNumber: phoneNumber,
                onComplete: () {
                  if (mounted) {
                    widget.onAuthSuccess?.call();
                  }
                },
              ),
            ),
          );
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _error = verifyResponse.message;
          _loading = false;
        });
      }
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _error = 'Failed to verify OTP: ${e.toString()}';
        _loading = false;
      });
    }
  }
}

  /*Future<void> _verifyOTP() async {
  if (_otpReference == null) return;

  setState(() {
    _loading = true;
    _error = null;
  });

  try {
    final verifyResponse = await OTPService.verifyOTP(
      reference: _otpReference!,
      otp: _otpController.text.trim(),
    );

    if (verifyResponse.success) {
      final phoneNumber = verifyResponse.phoneNumber!;
      print('✅ OTP verified successfully for: $phoneNumber');

      // ✅ Navigate to Onboarding screen after OTP
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => OnboardingScreen(
              phoneNumber: phoneNumber,
              onAuthSuccess: widget.onAuthSuccess,
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        setState(() {
          _error = verifyResponse.message;
          _loading = false;
        });
      }
    }
  } catch (e) {
    if (mounted) {
      setState(() {
        _error = 'Failed to verify OTP: ${e.toString()}';
        _loading = false;
      });
    }
  }
}*/



  Future<void> _createCustomUserSession(String phoneNumber, Map<String, dynamic>? userData) async {
    try {
      print('💾 [AUTH] Creating custom user session for: $phoneNumber');
      print('💾 [AUTH] User data received: $userData');
      
      // Create user document in Firestore without Firebase Auth
      final sessionData = {
        'phoneNumber': phoneNumber,
        'name': userData?['name'] ?? 'User',
        'email': userData?['email'],
        'dateOfBirth': userData?['dateOfBirth'],
        'createdAt': userData?['createdAt'],
        'lastLoginAt': FieldValue.serverTimestamp(),
        'isVerified': true,
        'isAuthenticated': true,
        'sessionId': DateTime.now().millisecondsSinceEpoch.toString(),
        'profileComplete': userData?['profileComplete'] ?? false,
      };
      
      // Remove null values
      sessionData.removeWhere((key, value) => value == null);
      
      print('📝 [AUTH] Session data to save: $sessionData');
      
      // Store in Firestore with a custom document ID
      final cleanPhoneNumber = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
      print('📝 [AUTH] Using clean phone number as document ID: $cleanPhoneNumber');
      
      final userDoc = FirebaseFirestore.instance.collection('users').doc(cleanPhoneNumber);
      await userDoc.set(sessionData, SetOptions(merge: true));
      
      print('✅ [AUTH] User session created successfully in Firestore with ID: ${userDoc.id}');
      await LocalSession.setCurrentUserId(userDoc.id);
      print('✅ [AUTH] Local session set with user ID: ${userDoc.id}');
      
    } catch (e) {
      print('❌ [AUTH] Error creating user session: $e');
      rethrow;
    }
  }

  void _resendOTP() {
    setState(() {
      _otpSent = false;
      _otpController.clear();
      _otpReference = null;
    });
    _sendOTP();
  }

  void _goBack() {
    setState(() {
      _otpSent = false;
      _otpController.clear();
      _otpReference = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height - 
                         MediaQuery.of(context).padding.top - 
                         MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: 32),
                  // Illustration
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Center(
                      child: Image.asset(
                        'assets/login.png',
                        height: 250,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const Spacer(),
                  
                  // Main content
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          Text(
                            _otpSent ? 'Enter Verification Code' : 'Welcome to SafeStep',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF7B3FA0),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _otpSent 
                              ? 'We sent a verification code to ${_phoneController.text}'
                              : 'Enter your phone number to get started',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          
                          if (!_otpSent) ...[
                            // Phone field only
                            TextFormField(
                              controller: _phoneController,
                              decoration: InputDecoration(
                                labelText: 'Phone Number',
                                hintText: '+94 77 123 4567',
                                prefixIcon: const Icon(Icons.phone),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.phone,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Phone number is required';
                                }
                                final digits = value.replaceAll(RegExp(r'[^\d]'), '');
                                if (digits.length < 9) {
                                  return 'Please enter a valid Sri Lankan phone number';
                                }
                                return null;
                              },
                            ),
                          ] else ...[
                            // OTP field
                            TextFormField(
                              controller: _otpController,
                              decoration: InputDecoration(
                                labelText: 'Verification Code',
                                hintText: 'XXXXXX',
                                hintStyle: TextStyle(
                                  color: Colors.grey.withOpacity(0.35),
                                  fontSize: 18,
                                ),
                                prefixIcon: const Icon(Icons.security),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 8,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Verification code is required';
                                }
                                if (value.length < 6) {
                                  return 'Please enter the complete verification code';
                                }
                                return null;
                              },
                            ),
                          ],
                          
                          const SizedBox(height: 24),
                          
                          // Error message
                          if (_error != null) ...[
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
                                  Expanded(
                                    child: Text(
                                      _error!,
                                      style: TextStyle(color: Colors.red.shade700),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          
                          // Main action button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _loading ? null : (_otpSent ? _verifyOTP : _sendOTP),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF7B3FA0),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _loading
                                  ? const CircularProgressIndicator(color: Colors.white)
                                  : Text(
                                      _otpSent ? 'Verify & Continue' : 'Send Verification Code',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                          
                          // Resend/Back button
                          if (_otpSent) ...[
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(
                                  onPressed: _loading ? null : _goBack,
                                  child: const Text(
                                    '← Change Number',
                                    style: TextStyle(color: Color(0xFF7B3FA0)),
                                  ),
                                ),
                                TextButton(
                                  onPressed: _loading ? null : _resendOTP,
                                  child: const Text(
                                    'Resend Code',
                                    style: TextStyle(color: Color(0xFF7B3FA0)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  
                  const Spacer(),
                  
                  // Footer
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24.0),
                    child: Text(
                      'By continuing, you agree to our Terms of Service and Privacy Policy',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
