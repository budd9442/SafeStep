import 'package:flutter/material.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

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
