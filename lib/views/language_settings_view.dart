
import 'package:flutter/material.dart';

class _LanguageOption {
  final String name;
  final String description;
  final IconData icon;
  const _LanguageOption({required this.name, required this.description, required this.icon});
}

class LanguageSettingsView extends StatefulWidget {
  const LanguageSettingsView({super.key});

  @override
  State<LanguageSettingsView> createState() => _LanguageSettingsViewState();
}

class _LanguageSettingsViewState extends State<LanguageSettingsView> {
  String selectedLanguage = 'English';
  final List<_LanguageOption> languages = [
    _LanguageOption(
      name: 'English',
      description: 'Use the app in English',
      icon: Icons.language,
    ),
    _LanguageOption(
      name: 'සිංහල (Sinhala)',
      description: 'ඇප් එක සිංහලෙන් භාවිතා කරන්න',
      icon: Icons.flag,
    ),
    _LanguageOption(
      name: 'தமிழ் (Tamil)',
      description: 'தமிழில் பயன்படுத்து',
      icon: Icons.flag,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Language Settings'),
        backgroundColor: const Color(0xFF8F5FE8),
        foregroundColor: Colors.white,
        elevation: 1,
      ),
      body: Container(
        color: const Color(0xFFF6F4FB),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ...languages.map((lang) {
              final isSelected = selectedLanguage == lang.name;
              return GestureDetector(
                onTap: () => setState(() => selectedLanguage = lang.name),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFE9E3F7) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF8F5FE8) : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: [
                      if (isSelected)
                        BoxShadow(
                          color: const Color(0xFF8F5FE8).withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                    ],
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isSelected ? const Color(0xFF8F5FE8) : const Color(0xFFE0E0E0),
                      child: Icon(lang.icon, color: Colors.white),
                    ),
                    title: Text(
                      lang.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        color: isSelected ? const Color(0xFF8F5FE8) : const Color(0xFF232946),
                      ),
                    ),
                    subtitle: Text(
                      lang.description,
                      style: TextStyle(
                        color: isSelected ? const Color(0xFF8F5FE8) : Colors.grey[700],
                        fontSize: 13,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Color(0xFF8F5FE8))
                        : null,
                  ),
                ),
              );
            }),
            const SizedBox(height: 32),
            Text(
              'Select your preferred language for the app interface. Changes will take effect immediately.',
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
  

