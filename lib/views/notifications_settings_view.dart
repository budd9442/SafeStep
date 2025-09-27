import 'package:flutter/material.dart';

class NotificationsSettingsView extends StatefulWidget {
  const NotificationsSettingsView({super.key});

  @override
  State<NotificationsSettingsView> createState() => _NotificationsSettingsViewState();
}

class _NotificationsSettingsViewState extends State<NotificationsSettingsView> {
  bool appNotifications = true;
  bool sosAlerts = true;
  bool vibration = true;
  bool sound = true;
  bool dailySummary = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications Settings'),
        backgroundColor: const Color(0xFF8F5FE8),
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: Container(
        color: const Color(0xFFF6F4FB),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
              color: Colors.white,
              child: SwitchListTile(
                title: const Text('App notifications', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                subtitle: const Text('Receive general notifications from the app.'),
                value: appNotifications,
                activeColor: const Color(0xFF8F5FE8),
                onChanged: (val) => setState(() => appNotifications = val),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
              color: Colors.white,
              child: SwitchListTile(
                title: const Text('SOS alerts', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                subtitle: const Text('Get notified for SOS and emergency alerts.'),
                value: sosAlerts,
                activeColor: const Color(0xFF8F5FE8),
                onChanged: (val) => setState(() => sosAlerts = val),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
              color: Colors.white,
              child: SwitchListTile(
                title: const Text('Vibration', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                subtitle: const Text('Vibrate on important notifications.'),
                value: vibration,
                activeColor: const Color(0xFF8F5FE8),
                onChanged: (val) => setState(() => vibration = val),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
              color: Colors.white,
              child: SwitchListTile(
                title: const Text('Sound', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                subtitle: const Text('Play sound for notifications.'),
                value: sound,
                activeColor: const Color(0xFF8F5FE8),
                onChanged: (val) => setState(() => sound = val),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
              color: Colors.white,
              child: SwitchListTile(
                title: const Text('Daily summary', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                subtitle: const Text('Receive a daily summary notification.'),
                value: dailySummary,
                activeColor: const Color(0xFF8F5FE8),
                onChanged: (val) => setState(() => dailySummary = val),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'You can manage your notification preferences here. For critical alerts, some notifications may be sent even if disabled.',
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
