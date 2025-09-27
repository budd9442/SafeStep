import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import '../services/local_session.dart';
import 'package:google_fonts/google_fonts.dart';

class AIPersonalizationScreen extends StatefulWidget {
  const AIPersonalizationScreen({Key? key}) : super(key: key);

  @override
  State<AIPersonalizationScreen> createState() => _AIPersonalizationScreenState();
}

class _AIPersonalizationScreenState extends State<AIPersonalizationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  
  String _selectedPersonality = 'supportive';
  bool _isEmergencyMode = false;
  bool _isLocationAware = true;
  
  File? _selectedImage;
  String? _currentImageUrl;
  bool _isLoading = false;
  bool _isSaving = false;

  final List<Map<String, dynamic>> _personalityOptions = [
    {'value': 'supportive', 'label': 'Supportive', 'description': 'Caring and empathetic'},
    {'value': 'professional', 'label': 'Professional', 'description': 'Direct and efficient'},
    {'value': 'friendly', 'label': 'Friendly', 'description': 'Warm and approachable'},
  ];

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentSettings() async {
    setState(() => _isLoading = true);
    
    try {
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null) return;

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(localUserId)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final aiSettings = data['aiAssistantSettings'] as Map<String, dynamic>? ?? {};
        
        setState(() {
          _nameController.text = aiSettings['name'] ?? 'SafeStep Assistant';
          _selectedPersonality = aiSettings['personality'] ?? 'supportive';
          _isEmergencyMode = aiSettings['emergencyMode'] ?? false;
          _isLocationAware = aiSettings['locationAware'] ?? true;
          _currentImageUrl = aiSettings['profileImageUrl'];
        });
      }
    } catch (e) {
      print('❌ [AI PERSONALIZATION] Error loading settings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load AI settings: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (pickedFile != null) {
        setState(() => _selectedImage = File(pickedFile.path));
      }
    } catch (e) {
      print('❌ [AI PERSONALIZATION] Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to pick image: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<String?> _uploadImage() async {
    if (_selectedImage == null) return _currentImageUrl;

    try {
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null) return null;

      final fileName = 'ai_assistant_${DateTime.now().millisecondsSinceEpoch}${path.extension(_selectedImage!.path)}';
      final ref = FirebaseStorage.instance.ref().child('ai_assistants/$localUserId/$fileName');

      final uploadTask = ref.putFile(_selectedImage!);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print('❌ [AI PERSONALIZATION] Error uploading image: $e');
      return null;
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null) {
        throw Exception('User not authenticated');
      }

      // Upload image if selected
      final imageUrl = await _uploadImage();

      final aiSettings = {
        'name': _nameController.text.trim(),
        'personality': _selectedPersonality,
        'emergencyMode': _isEmergencyMode,
        'locationAware': _isLocationAware,
        'profileImageUrl': imageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance
          .collection('users')
          .doc(localUserId)
          .set({
        'aiAssistantSettings': aiSettings,
      }, SetOptions(merge: true));

      print('✅ [AI PERSONALIZATION] Settings saved successfully');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI Assistant settings saved successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      print('❌ [AI PERSONALIZATION] Error saving settings: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save settings: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: Stack(
        children: [
          // Background gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF8F5FE8),
                  Color(0xFFE9E4F6),
                  Color(0xFFF8F9FF),
                ],
              ),
            ),
          ),
          
          // Content
          Column(
            children: [
              // Modern App Bar
              _buildModernAppBar(),
              
              // Settings Content
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              _buildProfileCard(),
                              const SizedBox(height: 20),
                              _buildBasicSettingsCard(),
                              const SizedBox(height: 20),
                              _buildPersonalityCard(),
                              const SizedBox(height: 20),
                              _buildSaveButton(),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 24,
        right: 24,
        bottom: 16,
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'AI Assistant',
              style: GoogleFonts.lato(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'Profile Picture',
              style: GoogleFonts.lato(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF232946),
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8F5FE8), Color(0xFF6C63FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF8F5FE8).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: _selectedImage != null
                    ? ClipOval(
                        child: Image.file(
                          _selectedImage!,
                          fit: BoxFit.cover,
                        ),
                      )
                    : _currentImageUrl != null
                        ? ClipOval(
                            child: Image.network(
                              _currentImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.person,
                                  size: 50,
                                  color: Colors.white,
                                );
                              },
                            ),
                          )
                        : const Icon(
                            Icons.person,
                            size: 50,
                            color: Colors.white,
                          ),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.camera_alt, size: 18),
              label: const Text('Change Photo'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8F5FE8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Basic Settings',
              style: GoogleFonts.lato(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF232946),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _nameController,
              style: GoogleFonts.lato(fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Assistant Name',
                hintText: 'e.g., SafeStep Assistant',
                labelStyle: GoogleFonts.lato(color: const Color(0xFF8F5FE8)),
                hintStyle: GoogleFonts.lato(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF8F5FE8), width: 2),
                ),
                prefixIcon: const Icon(Icons.person, color: Color(0xFF8F5FE8)),
                filled: true,
                fillColor: const Color(0xFFF8F9FF),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a name for your AI assistant';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              title: Text(
                'Emergency Mode',
                style: GoogleFonts.lato(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF232946),
                ),
              ),
              subtitle: Text(
                'More direct responses in emergencies',
                style: GoogleFonts.lato(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              value: _isEmergencyMode,
              onChanged: (value) {
                setState(() => _isEmergencyMode = value);
              },
              activeColor: const Color(0xFF8F5FE8),
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: Text(
                'Location Aware',
                style: GoogleFonts.lato(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF232946),
                ),
              ),
              subtitle: Text(
                'Use location for safety recommendations',
                style: GoogleFonts.lato(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              value: _isLocationAware,
              onChanged: (value) {
                setState(() => _isLocationAware = value);
              },
              activeColor: const Color(0xFF8F5FE8),
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalityCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personality',
              style: GoogleFonts.lato(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF232946),
              ),
            ),
            const SizedBox(height: 20),
            ..._personalityOptions.map((option) {
              final isSelected = _selectedPersonality == option['value'];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF8F5FE8).withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF8F5FE8) : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: RadioListTile<String>(
                  title: Text(
                    option['label'],
                    style: GoogleFonts.lato(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF232946),
                    ),
                  ),
                  subtitle: Text(
                    option['description'],
                    style: GoogleFonts.lato(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  value: option['value'],
                  groupValue: _selectedPersonality,
                  onChanged: (value) {
                    setState(() => _selectedPersonality = value!);
                  },
                  activeColor: const Color(0xFF8F5FE8),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSaveButton() {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8F5FE8), Color(0xFF6C63FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8F5FE8).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSaving ? null : _saveSettings,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isSaving
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Saving...',
                    style: GoogleFonts.lato(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              )
            : Text(
                'Save Settings',
                style: GoogleFonts.lato(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}
