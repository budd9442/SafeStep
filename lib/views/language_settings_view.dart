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

  // Translation map
  final Map<String, Map<String, String>> translations = {
    'English': {
      'title': 'Language Settings',
      'description': 'Select your preferred language for the app interface. Changes will take effect immediately.',
      'english': 'English',
      'english_desc': 'Use the app in English',
      'sinhala': 'සිංහල (Sinhala)',
      'sinhala_desc': 'ඇප් එක සිංහලෙන් භාවිතා කරන්න',
      'tamil': 'தமிழ் (Tamil)',
      'tamil_desc': 'தமிழில் பயன்படுத்து',
    },
    'සිංහල (Sinhala)': {
      'title': 'භාෂා සැකසුම්',
      'description': 'ඇප් අතුරුමුහුණත් සඳහා ඔබ කැමති භාෂාව තෝරන්න. වෙනස්කම් වහාම බලපායි.',
      'english': 'ඉංග්‍රීසි',
      'english_desc': 'ඇප් එක ඉංග්‍රීසි භාෂාවෙන් භාවිතා කරන්න',
      'sinhala': 'සිංහල (Sinhala)',
      'sinhala_desc': 'ඇප් එක සිංහලෙන් භාවිතා කරන්න',
      'tamil': 'தமிழ் (Tamil)',
      'tamil_desc': 'தமிழில் பயன்படுத்து',
    },
    'தமிழ் (Tamil)': {
      'title': 'மொழி அமைப்புகள்',
      'description': 'ஆப்பின் இடைமுகத்திற்கான விருப்ப மொழியைத் தேர்ந்தெடுக்கவும். மாற்றங்கள் உடனடியாக செயல்படும்.',
      'english': 'ஆங்கிலம்',
      'english_desc': 'ஆப்பை ஆங்கிலத்தில் பயன்படுத்தவும்',
      'sinhala': 'සිංහල (Sinhala)',
      'sinhala_desc': 'ඇප් එක සිංහලෙන් භාවිතා කරන්න',
      'tamil': 'தமிழ் (Tamil)',
      'tamil_desc': 'தமிழில் பயன்படுத்து',
    },
  };

  // Generate language options based on current selected language
  List<_LanguageOption> get languages => [
        _LanguageOption(
          name: translations[selectedLanguage]!['english']!,
          description: translations[selectedLanguage]!['english_desc']!,
          icon: Icons.language,
        ),
        _LanguageOption(
          name: translations[selectedLanguage]!['sinhala']!,
          description: translations[selectedLanguage]!['sinhala_desc']!,
          icon: Icons.flag,
        ),
        _LanguageOption(
          name: translations[selectedLanguage]!['tamil']!,
          description: translations[selectedLanguage]!['tamil_desc']!,
          icon: Icons.flag,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(translations[selectedLanguage]!['title']!),
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
                onTap: () => setState(() {
                  // Set selected language to the map key
                  if (lang.name.contains('English')) selectedLanguage = 'English';
                  else if (lang.name.contains('සිංහල')) selectedLanguage = 'සිංහල (Sinhala)';
                  else if (lang.name.contains('தமிழ்')) selectedLanguage = 'தமிழ் (Tamil)';
                }),
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
              translations[selectedLanguage]!['description']!,
              style: TextStyle(color: Colors.grey[700], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
