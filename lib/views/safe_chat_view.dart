import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';

class SafeChatView extends StatefulWidget {
  final bool internal;
  const SafeChatView({super.key, this.internal = false});
  @override
  State<SafeChatView> createState() => _SafeChatViewState();
}

class _SafeChatViewState extends State<SafeChatView> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, String>> _messages = [];
  bool _loading = false;

  Future<void> _sendMessage(String text) async {
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _loading = true;
    });
    _controller.clear();
    final response = await _fetchGeminiResponse(text);
    setState(() {
      _messages.add({'role': 'ai', 'content': response});
      _loading = false;
    });
  }

  Future<String> _fetchGeminiResponse(String prompt) async {
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=AIzaSyCenmB6mLRbKDAljElxTsNQtzySfWFWTjU');
    final res = await (await (await HttpClient().postUrl(uri))
      ..headers.contentType = ContentType.json
      ..write('{"contents":[{"parts":[{"text":"$prompt. You are a psychological support agent for distressed women. Respond with empathy, actionable advice, and encouragement."}]}]}')).close();
    final body = await res.transform(const Utf8Decoder()).join();
    final match = RegExp('"text":"([^"]+)"').firstMatch(body);
    return match != null ? match.group(1)!.replaceAll('\\n', '\n') : 'Sorry, I could not understand.';
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, i) {
              final msg = _messages[i];
              final isUser = msg['role'] == 'user';
              return Align(
                alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF8F5FE8) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    msg['content'] ?? '',
                    style: TextStyle(color: isUser ? Colors.white : Colors.black87),
                  ),
                ),
              );
            },
          ),
        ),
        if (_loading) const Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(),
        ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Type your message...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.send, color: Color(0xFF8F5FE8)),
                onPressed: _loading || _controller.text.trim().isEmpty
                    ? null
                    : () => _sendMessage(_controller.text.trim()),
              ),
            ],
          ),
        ),
      ],
    );
    if (widget.internal) return content;
    return Scaffold(appBar: AppBar(title: const Text('SafeChat')), body: content);
  }
}
