import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:safestep/services/local_session.dart';

class ProfileSettingsView extends StatefulWidget {
  const ProfileSettingsView({super.key});

  @override
  State<ProfileSettingsView> createState() => _ProfileSettingsViewState();
}

class _ProfileSettingsViewState extends State<ProfileSettingsView> {
  bool _loading = true;
  bool _savingUrl = false;
  bool _uploading = false;
  String? _userId;
  Map<String, dynamic>? _userData;
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
    });
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final localUserId = await LocalSession.getCurrentUserId();
      if (localUserId == null || localUserId.isEmpty) {
        setState(() {
          _userId = null;
          _userData = null;
          _loading = false;
        });
        return;
      }
      final doc = await FirebaseFirestore.instance.collection('users').doc(localUserId).get();
      setState(() {
        _userId = localUserId;
        _userData = doc.data() ?? {};
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickAndUpload() async {
    setState(() => _uploading = true);
    try {
      if (_userId == null) return;
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final ref = FirebaseStorage.instanceFor(bucket: 'gs://safestep-d8237.firebasestorage.app')
            .ref()
            .child('profile_pics/${_userId}.jpg');
        await ref.putFile(file);
        await Future.delayed(const Duration(milliseconds: 500));
        final newUrl = await ref.getDownloadURL();
        final cacheBuster = DateTime.now().millisecondsSinceEpoch.toString();
        final finalUrl = '$newUrl?cb=$cacheBuster';

        await FirebaseFirestore.instance.collection('users').doc(_userId).set({
          'profilePicUrl': finalUrl,
          'profilePic': finalUrl,
        }, SetOptions(merge: true));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated')));
          await _loadProfile();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload: $e')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a URL')));
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL must start with http:// or https://')));
      return;
    }
    setState(() => _savingUrl = true);
    try {
      if (_userId == null) return;
      await FirebaseFirestore.instance.collection('users').doc(_userId).set({
        'profilePicUrl': url,
        'profilePic': url,
      }, SetOptions(merge: true));
      if (mounted) {
        _urlController.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture URL saved')));
        await _loadProfile();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save URL: $e')));
      }
    } finally {
      if (mounted) setState(() => _savingUrl = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Modern gradient background
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
              
              // Profile Content
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            _buildProfileCard(),
                            const SizedBox(height: 20),
                            _buildProfileInfoCard(),
                            const SizedBox(height: 32),
                          ],
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
          // Back button
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
          // Title
          Expanded(
            child: Text(
              'Profile Settings',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
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
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Profile Picture
          Stack(
            children: [
              CircleAvatar(
                radius: 60,
                backgroundColor: const Color(0xFF8F5FE8).withOpacity(0.1),
                backgroundImage: (() {
                  final url = (_userData?['profilePicUrl'] ?? _userData?['profilePic']) as String?;
                  if (url != null && url.isNotEmpty) {
                    return NetworkImage(url);
                  }
                  return null;
                })(),
                child: ((_userData?['profilePicUrl'] ?? _userData?['profilePic']) == null)
                    ? const Icon(Icons.person, size: 60, color: Color(0xFF8F5FE8))
                    : null,
              ),
              // Edit button overlay
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF8F5FE8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                    onPressed: _showProfilePicOptions,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // User Name
          Text(
            (_userData?['name'] ?? 'User').toString(),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF232946),
            ),
          ),
          const SizedBox(height: 8),
          
          // Phone Number
          Text(
            (_userData?['phoneNumber'] ?? '').toString(),
            style: const TextStyle(
              fontSize: 16,
              color: Color(0xFF777B84),
            ),
          ),
          const SizedBox(height: 20),
          
          // Action Buttons
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  icon: Icons.upload,
                  label: 'Upload Photo',
                  onPressed: _uploading ? null : _pickAndUpload,
                  isLoading: _uploading,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionButton(
                  icon: Icons.link,
                  label: 'Set URL',
                  onPressed: _showUrlDialog,
                  isLoading: _savingUrl,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8F5FE8), Color(0xFFB9A6F6)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        icon: isLoading
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Icon(icon, color: Colors.white, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildProfileInfoCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profile Information',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF232946),
            ),
          ),
          const SizedBox(height: 20),
          _buildInfoTile('Name', (_userData?['name'] ?? 'User').toString()),
          _buildInfoTile('Phone', (_userData?['phoneNumber'] ?? '').toString()),
          if ((_userData?['email'] ?? '') != null && (_userData?['email'] ?? '').toString().isNotEmpty)
            _buildInfoTile('Email', (_userData?['email'] ?? '').toString()),
          if (_userData?['dateOfBirth'] != null)
            _buildInfoTile('Date of birth', _formatDate(_userData?['dateOfBirth'])),
          _buildInfoTile('Profile complete', ((_userData?['profileComplete'] ?? false) == true) ? 'Yes' : 'No'),
        ],
      ),
    );
  }

  void _showProfilePicOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Update Profile Picture',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF232946),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.upload,
                    label: 'Upload Photo',
                    onPressed: _uploading ? null : _pickAndUpload,
                    isLoading: _uploading,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionButton(
                    icon: Icons.link,
                    label: 'Set URL',
                    onPressed: _showUrlDialog,
                    isLoading: _savingUrl,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showUrlDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Set Profile Picture URL',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF232946),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                hintText: 'https://example.com/image.jpg',
                hintStyle: const TextStyle(color: Color(0xFF777B84)),
                filled: true,
                fillColor: const Color(0xFFF6F6F6),
                contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFF8F5FE8), width: 2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: _buildActionButton(
                icon: Icons.save,
                label: 'Save URL',
                onPressed: _savingUrl
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _saveUrl();
                      },
                isLoading: _savingUrl,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF8F5FE8).withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF777B84),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value.isEmpty ? '-' : value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF232946),
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.info_outline,
            color: const Color(0xFF8F5FE8).withOpacity(0.6),
            size: 20,
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic ts) {
    try {
      if (ts is Timestamp) {
        final d = ts.toDate();
        return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      }
      return ts.toString();
    } catch (_) {
      return ts.toString();
    }
  }
}


