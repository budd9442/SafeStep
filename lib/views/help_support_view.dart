import 'package:flutter/material.dart';

class HelpSupportView extends StatelessWidget {
  const HelpSupportView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & Support'),
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
              child: ExpansionTile(
                title: const Text('Frequently Asked Questions', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                children: [
                  ListTile(
                    title: const Text('How do I reset my password?'),
                    subtitle: const Text('Go to Profile > Settings > Change Password.'),
                  ),
                  ListTile(
                    title: const Text('How do I contact support?'),
                    subtitle: const Text('Use the Contact Support button below or email support@safestep.com.'),
                  ),
                  ListTile(
                    title: const Text('How do I report a bug or problem?'),
                    subtitle: const Text('Tap the Report a Problem button below and describe your issue.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                leading: const Icon(Icons.support_agent, color: Color(0xFF8F5FE8)),
                title: const Text('Contact Support', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Get help from our support team.'),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Contact Support'),
                      content: const Text('Email: support@safestep.com\nPhone: +1-800-123-4567'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
              color: Colors.white,
              child: ListTile(
                leading: const Icon(Icons.bug_report, color: Color(0xFF8F5FE8)),
                title: const Text('Report a Problem', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Let us know if you find a bug or issue.'),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Report a Problem'),
                      content: const Text('Please email a description of the problem to bugs@safestep.com.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                'SafeStep App v1.0.0',
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
