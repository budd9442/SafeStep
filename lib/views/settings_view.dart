import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
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
          setState(() {
            // This will force FutureBuilder to refetch
            _profilePicFuture = Future.value('$newUrl?cb=$cacheBuster');
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
            if (_uploading) {
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
        onTap: _pickAndUpload,
      ),
    );
  }

  Future<String?> _getProfilePicUrl(User? user) async {
    if (user == null) return null;
    try {
      final ref = FirebaseStorage.instanceFor(bucket: 'gs://safestep-d8237.firebasestorage.app/profile_pics').ref().child('profile_pics/${user.uid}.jpg');
      final url = await ref.getDownloadURL();
      // Add cache-busting query param
      return '$url?t=${DateTime.now().millisecondsSinceEpoch}';
    } catch (_) {
      return null;
    }
  }
}
