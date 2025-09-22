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
      appBar: AppBar(
        title: const Text('Profile Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundImage: (() {
                            final url = (_userData?['profilePicUrl'] ?? _userData?['profilePic']) as String?;
                            if (url != null && url.isNotEmpty) {
                              return NetworkImage(url);
                            }
                            return null;
                          })(),
                          child: ((_userData?['profilePicUrl'] ?? _userData?['profilePic']) == null)
                              ? const Icon(Icons.person, size: 48)
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _uploading ? null : _pickAndUpload,
                              icon: const Icon(Icons.upload),
                              label: _uploading
                                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Text('Change photo'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (ctx) {
                                    return Padding(
                                      padding: EdgeInsets.only(
                                        left: 16,
                                        right: 16,
                                        bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                                        top: 16,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Set from URL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: _urlController,
                                            decoration: const InputDecoration(
                                              hintText: 'https://example.com/image.jpg',
                                              border: OutlineInputBorder(),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: ElevatedButton(
                                              onPressed: _savingUrl
                                                  ? null
                                                  : () async {
                                                      Navigator.pop(ctx);
                                                      await _saveUrl();
                                                    },
                                              child: _savingUrl
                                                  ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                                  : const Text('Save'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                              icon: const Icon(Icons.link),
                              label: const Text('Set from URL'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text('Profile information', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 12),
                  _infoTile('Name', (_userData?['name'] ?? 'User').toString()),
                  _infoTile('Phone', (_userData?['phoneNumber'] ?? '').toString()),
                  if ((_userData?['email'] ?? '') != null && (_userData?['email'] ?? '').toString().isNotEmpty)
                    _infoTile('Email', (_userData?['email'] ?? '').toString()),
                  if (_userData?['dateOfBirth'] != null)
                    _infoTile('Date of birth', _formatDate(_userData?['dateOfBirth'])),
                  _infoTile('Profile complete', ((_userData?['profileComplete'] ?? false) == true) ? 'Yes' : 'No'),
                ],
              ),
            ),
    );
  }

  Widget _infoTile(String label, String value) {
    return Card(
      elevation: 0,
      color: const Color(0xFFF6F4FB),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(value.isEmpty ? '-' : value),
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


