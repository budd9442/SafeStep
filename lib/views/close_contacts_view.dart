import 'package:flutter/material.dart';

class CloseContactsView extends StatelessWidget {
  final bool internal;
  const CloseContactsView({super.key, this.internal = false});
  @override
  Widget build(BuildContext context) {
    final content = ListView(
      padding: const EdgeInsets.all(18),
      children: [
        ListTile(
          leading: const Icon(Icons.person, color: Color(0xFF8F5FE8)),
          title: const Text('Add/Edit Close Contacts'),
          trailing: IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Edit Contact'),
                  content: const Text('Contact editing UI goes here.'),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
                ),
              );
            },
          ),
        ),
      ],
    );
    if (internal) return content;
    return Scaffold(appBar: AppBar(title: const Text('Close Contacts')), body: content);
  }
}
