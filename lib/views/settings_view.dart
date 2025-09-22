import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:safestep/views/map_view.dart';

class SettingsView extends StatelessWidget {
  final ValueChanged<String>? onProfilePicChanged;
  final GlobalKey<MapViewState>? mapViewKey;
  const SettingsView({super.key, this.onProfilePicChanged, this.mapViewKey});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF6F4FB),
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          const Text(
            'Settings',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Color(0xFF8F5FE8),
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 18),
          _SettingsTile(icon: Icons.lock, label: 'Privacy'),
          _SettingsTile(icon: Icons.notifications, label: 'Notifications'),
          _SettingsTile(icon: Icons.language, label: 'Language'),
          _SettingsTile(icon: Icons.help, label: 'Help & Support'),
          const SizedBox(height: 24),
          _ProfilePictureTile(
            onProfilePicChanged: onProfilePicChanged,
            mapViewKey: mapViewKey,
          ),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SettingsTile({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white,
      child: ListTile(
        leading: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF8F5FE8), Color(0xFF6C63FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: Colors.white, size: 26),
        ),
        title: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 17,
            color: Color(0xFF232946),
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF8F5FE8), size: 18),
        onTap: () {},
      ),
    );
  }
}

class _ProfilePictureTile extends StatefulWidget {
  final ValueChanged<String>? onProfilePicChanged;
  final GlobalKey<MapViewState>? mapViewKey;
  const _ProfilePictureTile({Key? key, this.onProfilePicChanged, this.mapViewKey}) : super(key: key);

  @override
  State<_ProfilePictureTile> createState() => _ProfilePictureTileState();
}

class _ProfilePictureTileState extends State<_ProfilePictureTile> {
  bool _uploading = false;
  bool _savingUrl = false;
  final TextEditingController _urlController = TextEditingController();

  Future<void> _pickAndUpload() async {
    setState(() => _uploading = true);
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final ref = FirebaseStorage.instanceFor(bucket: 'gs://safestep-d8237.firebasestorage.app').ref().child('profile_pics/${user.uid}.jpg');
          await ref.putFile(file);
          // Wait a moment for CDN to update
          await Future.delayed(const Duration(milliseconds: 500));
          // Get a fresh download URL and random cache-buster
          final newUrl = await ref.getDownloadURL();
          final cacheBuster = DateTime.now().millisecondsSinceEpoch.toString() + '_' + (DateTime.now().microsecondsSinceEpoch % 1000).toString();
          final finalUrl = '$newUrl?cb=$cacheBuster';
          
          // Save the profile picture URL to Firestore
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'profilePicUrl': finalUrl,
            'profilePic': finalUrl, // Keep both fields for backward compatibility
          }, SetOptions(merge: true));
          
          setState(() {
            // This will force FutureBuilder to refetch
            _profilePicFuture = Future.value(finalUrl);
          });
          PaintingBinding.instance.imageCache.clear();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated!')));
          if (widget.mapViewKey?.currentState != null) {
            await widget.mapViewKey!.currentState!.refreshProfilePointerMarker();
          }
          if (widget.onProfilePicChanged != null) widget.onProfilePicChanged!(file.path);
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to upload: $e')));
    } finally {
      setState(() => _uploading = false);
    }
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a URL')));
      return;
    }

    // Basic URL validation
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a valid URL (starting with http:// or https://)')));
      return;
    }

    setState(() => _savingUrl = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Save the profile picture URL to Firestore
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'profilePicUrl': url,
          'profilePic': url, // Keep both fields for backward compatibility
        }, SetOptions(merge: true));
        
        setState(() {
          // This will force FutureBuilder to refetch
          _profilePicFuture = Future.value(url);
        });
        PaintingBinding.instance.imageCache.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture URL saved!')));
        if (widget.mapViewKey?.currentState != null) {
          await widget.mapViewKey!.currentState!.refreshProfilePointerMarker();
        }
        _urlController.clear();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save URL: $e')));
    } finally {
      setState(() => _savingUrl = false);
    }
  }

  void _showProfilePicOptions() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProfilePicOptionsSheet(
        onUpload: _pickAndUpload,
        onSaveUrl: _saveUrl,
        urlController: _urlController,
        uploading: _uploading,
        savingUrl: _savingUrl,
      ),
    );
  }

  // Add a field to hold the future for the profile pic URL
  late Future<String?> _profilePicFuture = _getProfilePicUrl(FirebaseAuth.instance.currentUser);

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 10),
      color: Colors.white,
      child: ListTile(
        leading: FutureBuilder<String?>(
          future: _profilePicFuture,
          builder: (context, snapshot) {
            if (_uploading || _savingUrl) {
              return const CircleAvatar(radius: 24, child: CircularProgressIndicator());
            }
            if (snapshot.hasData && snapshot.data != null) {
              return CircleAvatar(radius: 24, backgroundImage: NetworkImage(snapshot.data!));
            }
            return const CircleAvatar(radius: 24, child: Icon(Icons.person, size: 28));
          },
        ),
        title: const Text('Profile Picture', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17, color: Color(0xFF232946))),
        trailing: const Icon(Icons.edit, color: Color(0xFF8F5FE8), size: 22),
        onTap: _showProfilePicOptions,
      ),
    );
  }

  Future<String?> _getProfilePicUrl(User? user) async {
    if (user == null) return null;
    try {
      // First try to get the profile picture URL from Firestore
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final profilePicUrl = userData?['profilePicUrl'] ?? userData?['profilePic'];
      
      if (profilePicUrl != null && profilePicUrl.isNotEmpty) {
        return profilePicUrl;
      }
      
      // Fallback to Firebase Storage
      final ref = FirebaseStorage.instanceFor(bucket: 'gs://safestep-d8237.firebasestorage.app').ref().child('profile_pics/${user.uid}.jpg');
      final url = await ref.getDownloadURL();
      // Add cache-busting query param
      return '$url?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }
}

class _ProfilePicOptionsSheet extends StatelessWidget {
  final VoidCallback onUpload;
  final VoidCallback onSaveUrl;
  final TextEditingController urlController;
  final bool uploading;
  final bool savingUrl;

  const _ProfilePicOptionsSheet({
    required this.onUpload,
    required this.onSaveUrl,
    required this.urlController,
    required this.uploading,
    required this.savingUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 32,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Update Profile Picture',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
          ),
          const SizedBox(height: 24),
          
          // Upload from device option
          Card(
            elevation: 0,
            color: const Color(0xFFF6F4FB),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF8F5FE8), Color(0xFF6C63FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(Icons.upload, color: Colors.white, size: 20),
              ),
              title: const Text('Upload from Device', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Choose an image from your gallery'),
              onTap: uploading ? null : () {
                Navigator.pop(context);
                onUpload();
              },
              trailing: uploading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
            ),
          ),
          
          const SizedBox(height: 16),
          
          // URL input option
          Card(
            elevation: 0,
            color: const Color(0xFFF6F4FB),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF8F5FE8), Color(0xFF6C63FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(Icons.link, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Text('Enter Image URL', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlController,
                    decoration: InputDecoration(
                      hintText: 'https://example.com/image.jpg',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: savingUrl ? null : () {
                        Navigator.pop(context);
                        onSaveUrl();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8F5FE8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: savingUrl
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save URL', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
