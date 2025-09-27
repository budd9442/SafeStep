import 'package:flutter/material.dart';

class PrivacySettingsView extends StatefulWidget {
  const PrivacySettingsView({super.key});

  @override
  State<PrivacySettingsView> createState() => _PrivacySettingsViewState();
}

class _PrivacySettingsViewState extends State<PrivacySettingsView> {
  bool showProfile = true;
  bool allowLocation = true;
  bool activityStatus = false;
  bool personalizedAds = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Settings'),
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
                title: const Text('Show my profile to others', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                subtitle: const Text('Allow your profile to be visible to other users.'),
                value: showProfile,
                activeColor: const Color(0xFF8F5FE8),
                onChanged: (val) => setState(() => showProfile = val),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
              color: Colors.white,
              child: SwitchListTile(
                title: const Text('Allow location access', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                subtitle: const Text('Enable location-based features and services.'),
                value: allowLocation,
                activeColor: const Color(0xFF8F5FE8),
                onChanged: (val) => setState(() => allowLocation = val),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
              color: Colors.white,
              child: SwitchListTile(
                title: const Text('Enable activity status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                subtitle: const Text('Let others see when you are active.'),
                value: activityStatus,
                activeColor: const Color(0xFF8F5FE8),
                onChanged: (val) => setState(() => activityStatus = val),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
              color: Colors.white,
              child: SwitchListTile(
                title: const Text('Personalized ads', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                subtitle: const Text('Allow app to show you personalized ads.'),
                value: personalizedAds,
                activeColor: const Color(0xFF8F5FE8),
                onChanged: (val) => setState(() => personalizedAds = val),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'You can change your privacy preferences at any time. For more information, see our Privacy Policy.',
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
