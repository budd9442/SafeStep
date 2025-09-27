import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:safestep/services/local_session.dart';

class CloseContactsView extends StatefulWidget {
  const CloseContactsView({super.key});
  @override
  State<CloseContactsView> createState() => _CloseContactsViewState();
}

class _CloseContactsViewState extends State<CloseContactsView> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _userId;
  bool _showEmergency = false;

  @override
  void initState() {
    super.initState();
    _getCurrentUserId();
  }

  Future<void> _getCurrentUserId() async {
    try {
      final localUserId = await LocalSession.getCurrentUserId();
      if (!mounted) return;
      setState(() {
        _userId = localUserId;
      });
    } catch (e) {
      print('Error getting current user ID: $e');
    }
  }

  Future<void> _addContact() async {
    if (!_formKey.currentState!.validate()) return;
    if (_userId == null) {
      setState(() { _error = 'User not authenticated'; _loading = false; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final contacts = await _getContacts();
      if (contacts.length >= 5) {
        setState(() { _error = 'You can only add up to 5 contacts.'; _loading = false; });
        return;
      }
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId!)
          .collection('contacts')
          .add({
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _nameController.clear();
      _phoneController.clear();
      Navigator.of(context).pop();
    } catch (e) {
      setState(() { _error = 'Failed to add contact.'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<List<Map<String, dynamic>>> _getContacts() async {
    if (_userId == null) return [];
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_userId!)
        .collection('contacts')
        .orderBy('createdAt')
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  Future<void> _deleteContact(String id) async {
    if (_userId == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(_userId!)
        .collection('contacts')
        .doc(id)
        .delete();
  }

  void _showAddContactDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 32,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add Close Contact', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF7B3FA0))),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Name required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) => v == null || v.trim().isEmpty ? 'Phone required' : null,
              ),
              const SizedBox(height: 24),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _addContact,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7B3FA0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Add Contact', style: TextStyle(color: Colors.white, fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {
                    if (_showEmergency) setState(() { _showEmergency = false; });
                  },
                  child: Column(
                    children: [
                      Icon(Icons.group, size: 32, color: !_showEmergency ? Color(0xFF7B3FA0) : Colors.grey),
                      Text('Friends', style: TextStyle(fontSize: 12, color: !_showEmergency ? Color(0xFF7B3FA0) : Colors.grey)),
                    ],
                  ),
                ),
                const SizedBox(width: 32),
                GestureDetector(
                  onTap: () {
                    if (!_showEmergency) setState(() { _showEmergency = true; });
                  },
                  child: Column(
                    children: [
                      Icon(Icons.local_hospital, size: 32, color: _showEmergency ? Color(0xFFD32F2F) : Colors.grey),
                      Text('Emergency', style: TextStyle(fontSize: 12, color: _showEmergency ? Color(0xFFD32F2F) : Colors.grey)),
                    ],
                  ),
                ),
              ],
            ),
            
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF8F6FC),
      body: _showEmergency
          ? const EmergencyContactsView()
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 18),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Your Trusted Contacts', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF7B3FA0))),
                      ElevatedButton.icon(
                        onPressed: _showAddContactDialog,
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text('Add', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF7B3FA0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _userId == null 
                      ? const Center(child: CircularProgressIndicator())
                      : StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('users')
                              .doc(_userId!)
                              .collection('contacts')
                              .orderBy('createdAt')
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final docs = snapshot.data?.docs ?? [];
                            if (docs.isEmpty) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.group, size: 80, color: Colors.grey.shade300),
                                    const SizedBox(height: 16),
                                    const Text('No contacts yet. Add your trusted contacts!', style: TextStyle(fontSize: 16, color: Colors.grey)),
                                  ],
                                ),
                              );
                            }
                            return ListView.separated(
                              padding: const EdgeInsets.all(18),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, i) {
                                final data = docs[i].data() as Map<String, dynamic>;
                                return Card(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 3,
                                  child: ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFFEEE6FA),
                                      child: const Icon(Icons.person, color: Color(0xFF7B3FA0)),
                                    ),
                                    title: Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    subtitle: Text(data['phone'] ?? '', style: const TextStyle(color: Colors.black87)),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteContact(docs[i].id),
                                      tooltip: 'Delete',
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class EmergencyContactsView extends StatelessWidget {
  const EmergencyContactsView({super.key});

  @override
  Widget build(BuildContext context) {
    final emergencyContacts = [
      {'name': 'Police', 'phone': '100'},
      {'name': 'Ambulance', 'phone': '101'},
      {'name': 'Fire Brigade', 'phone': '102'},
      {'name': 'Women Helpline', 'phone': '1091'},
      {'name': 'Disaster Management', 'phone': '108'},
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              Text('Emergency Contacts', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFFD32F2F))),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(18),
            itemCount: emergencyContacts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final data = emergencyContacts[i];
              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 3,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFFDE0E0),
                    child: const Icon(Icons.local_hospital, color: Color(0xFFD32F2F)),
                  ),
                  title: Text(data['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(data['phone'] ?? '', style: const TextStyle(color: Colors.black87)),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
