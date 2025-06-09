import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_chat_bubble/chat_bubble.dart';
import 'package:flutter_chat_bubble/bubble_type.dart';
import 'package:flutter_chat_bubble/clippers/chat_bubble_clipper_1.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class SafeChatView extends StatefulWidget {
  final bool internal;
  const SafeChatView({super.key, this.internal = false});
  @override
  State<SafeChatView> createState() => _SafeChatViewState();
}

class _SafeChatViewState extends State<SafeChatView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [
    {
      'role': 'ai',
      'content': 'Hi, I\'m here to support you. How are you feeling today?',
      'timestamp': DateTime.now().subtract(const Duration(minutes: 2)),
    },
  ];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _messages.add({
        'role': 'user',
        'content': text,
        'timestamp': DateTime.now(),
      });
      _loading = true;
    });
    _controller.clear();
    _scrollToBottom();
    final response = await fetchGeminiResponse(text);
    setState(() {
      _messages.add({
        'role': 'ai',
        'content': response,
        'timestamp': DateTime.now(),
      });
      _loading = false;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }



Future<String> fetchGeminiResponse(String prompt) async {
  final apiKey = dotenv.env['GEMINI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    return 'Sorry, I could not understand. (MISSING API KEY)';
  }

  final uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey',
  );

  // Build conversation history for context
  List<Map<String, dynamic>> history = _messages
      .where((m) => m['role'] == 'user' || m['role'] == 'ai')
      .map((m) => {
            'role': m['role'] == 'ai' ? 'model' : 'user',
            'parts': [
              {'text': m['content'] ?? ''}
            ]
          })
      .toList();
  // Add the new user prompt as the last message
  history.add(<String, Object>{
    'role': 'user',
    'parts': [
      {'text': prompt}
    ]
  });

  final headers = {'Content-Type': 'application/json'};
  final body = jsonEncode({
    "contents": history,
    "generationConfig": {
      "temperature": 0.6,
      "topP": 0.8,
      "topK": 40,
      "maxOutputTokens": 128 // Shorter replies
    },
    "tools": [
      {
        "functionDeclarations": [
          {
            "name": "support_agent",
            "description": "Reply as a psychological support agent for distressed women. For every reply, also do a risk analysis of the user's message and your response. Never suggest risky, illegal, or unsafe activities, even if the user asks. Understand context, keep replies short, sweet, and unformatted. Always reply in Sinhala or Tamil, matching the user's language or preference. If the user uses Singlish greetings (hlo, halo, haloo), reply in Sinhala. You may reply in Tamil if the user uses Tamil. You can suggest features from this app if relevant (e.g., fake call, panic button, safe chat, location sharing, etc). Never give medical or legal advice.",
            "parameters": {
              "type": "object",
              "properties": {
                "message": {"type": "string", "description": "Short, supportive, actionable response. No formatting."},
                "risk_analysis": {"type": "string", "description": "Brief risk analysis of the user's message and the response. Warn if any risk is detected."}
              },
              "required": ["message", "risk_analysis"]
            }
          }
        ]
      }
    ]
  });

  try {
    final response = await http.post(uri, headers: headers, body: body);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // Try to extract from functionCall if present
      final functionCall = data['candidates']?[0]['content']?['parts']?[0]['functionCall'];
      if (functionCall != null && functionCall['name'] == 'support_agent') {
        final message = functionCall['args']?['message'];
        final risk = functionCall['args']?['risk_analysis'];
        if (message != null && message is String && message.isNotEmpty) {
          if (risk != null && risk is String && risk.isNotEmpty) {
            return message.trim() + '\n\n(Risk analysis: ' + risk.trim() + ')';
          }
          return message.trim();
        }
      }
      // Fallback to normal text
      final text = data['candidates']?[0]['content']?['parts']?[0]['text'];
      return text != null ? text.toString().trim() : 'Sorry, no response.';
    } else {
      return 'Error: \\${response.statusCode} - \\${response.reasonPhrase}\nBody: \\${response.body}';
    }
  } catch (e) {
    return 'Something went wrong: $e';
  }
}


  Widget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF8F5FE8), Color(0xFFB9A6F6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage: const NetworkImage('https://api.dicebear.com/7.x/bottts/svg?seed=ai'),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AI Assistant',
                  style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 18)),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('Online',
                      style: GoogleFonts.lato(fontSize: 12, color: Colors.white70)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> msg, bool isUser, Animation<double> animation) {
    final time = DateFormat('h:mm a').format(msg['timestamp'] as DateTime);
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: 0.0,
      child: ChatBubble(
        clipper: ChatBubbleClipper1(type: isUser ? BubbleType.sendBubble : BubbleType.receiverBubble),
        alignment: isUser ? Alignment.topRight : Alignment.topLeft,
        margin: const EdgeInsets.symmetric(vertical: 4),
        backGroundColor: isUser ? const Color(0xFF8F5FE8) : Colors.grey[200]!,
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg['content'] ?? '',
              style: GoogleFonts.lato(
                color: isUser ? Colors.white : Colors.black87,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: GoogleFonts.lato(
                color: isUser ? Colors.white70 : Colors.black54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ).animate().fade(duration: 350.ms).slideY(begin: 0.2, end: 0, duration: 350.ms),
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.emoji_emotions_outlined, color: Color(0xFF8F5FE8)),
            onPressed: () {}, // TODO: Emoji picker
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              style: GoogleFonts.lato(fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'Type your message...',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.attach_file, color: Color(0xFF8F5FE8)),
            onPressed: () {}, // TODO: Media picker
          ),
          const SizedBox(width: 2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _loading
                ? const SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8F5FE8)),
                  )
                : IconButton(
                    key: ValueKey(_controller.text.isNotEmpty),
                    icon: const Icon(Icons.send, color: Color(0xFF8F5FE8)),
                    onPressed: _controller.text.trim().isEmpty || _loading
                        ? null
                        : () => _sendMessage(_controller.text.trim()),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFF3EFFF), Color(0xFFE9E4F6), Color(0xFFD6D0F2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Stack(
      children: [
        _buildBackground(),
        Column(
          children: [
            Expanded(
              child: AnimatedList(
                key: ValueKey(_messages.length),
                controller: _scrollController,
                reverse: true,
                initialItemCount: _messages.length,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
                itemBuilder: (context, i, animation) {
                  final msg = _messages[_messages.length - 1 - i];
                  final isUser = msg['role'] == 'user';
                  return _buildMessageBubble(msg, isUser, animation);
                },
              ),
            ),
            _buildInputBar(),
          ],
        ),
      ],
    );
    if (widget.internal) return content;
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: _buildAppBar(),
      ),
      body: SafeArea(child: content),
    );
  }
}
