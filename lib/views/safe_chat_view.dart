import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_chat_bubble/chat_bubble.dart';
import 'package:flutter_chat_bubble/bubble_type.dart';
import 'package:flutter_chat_bubble/clippers/chat_bubble_clipper_1.dart';
import 'package:intl/intl.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

class SafeChatView extends StatefulWidget {
  final bool internal;
  final String? initialMessage;
  const SafeChatView({super.key, this.internal = false, this.initialMessage});
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
  void initState() {
    super.initState();
    if (widget.initialMessage != null && widget.initialMessage!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sendMessage(widget.initialMessage!);
      });
    }
  }

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
    // Check for action command in the response (JSON parse if needed)
    String displayResponse = response;
    try {
      // Try to parse as JSON if response looks like a JSON object
      if (response.trim().startsWith('{') && response.trim().endsWith('}')) {
        final Map<String, dynamic> respObj = jsonDecode(response);
        debugPrint('[AI AGENT] Full AI response: ' + response);
        displayResponse = respObj['message'] ?? response;
        // Only append risk analysis if not already included in the message
        // (Assume Gemini already includes it if needed)
        // Remove this block to avoid double risk analysis
        // if (respObj['risk_analysis'] != null) {
        //   displayResponse += '\n\n(Risk analysis: ' + respObj['risk_analysis'] + ')';
        // }
        if (respObj['action'] != null && respObj['action']['type'] == 'fake_call') {
          debugPrint('[AI AGENT] Triggering fake call with params: ' + respObj['action']['params'].toString());
          final params = respObj['action']['params'] ?? {};
          await _triggerFakeCallFromAgent(params);
        }
      } else {
        debugPrint('[AI AGENT] AI response (no action): ' + response);
      }
    } catch (e) {
      debugPrint('[AI AGENT] Error parsing action: $e');
    }
    setState(() {
      _messages.add({
        'role': 'ai',
        'content': displayResponse,
        'timestamp': DateTime.now(),
      });
      _loading = false;
    });
    _scrollToBottom();
  }

  Future<void> _triggerFakeCallFromAgent(Map params) async {
    const platform = MethodChannel('com.example.safestep/fakecall');
    try {
      debugPrint('[AI AGENT] Invoking MethodChannel for fake call with params: \\$params');
      await platform.invokeMethod('triggerFakeCall', params);
      debugPrint('[AI AGENT] Fake call triggered successfully.');
    } catch (e) {
      debugPrint('[AI AGENT] Error triggering fake call: \\$e');
    }
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
    return jsonEncode({
      'message': 'Sorry, I could not understand. (MISSING API KEY)',
      'risk_analysis': 'API key missing. Cannot analyze risk.'
    });
  }

  // Gather device context: location, time, etc.
  String? locationString;
  try {
    // Use Geolocator to get current position if available
    // (Assumes Geolocator is available in your project)
    // If not, you can inject location from parent widget
    // or pass as a parameter.
    // For now, just use a placeholder:
    locationString = 'Unavailable';
  } catch (_) {
    locationString = 'Unavailable';
  }
  final now = DateTime.now();
  final timeString = now.toIso8601String();

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

  // Add device context as a system message (fix type error)
  history.insert(0, <String, Object>{
    'role': 'user',
    'parts': <Object>[
      <String, Object>{'text': '[DEVICE_CONTEXT] Current time: $timeString\nLocation: $locationString'}
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
            "description": "Reply as a psychological support agent for distressed women. For every reply, also do a risk analysis of the user's message and your response. Never suggest risky, illegal, or unsafe activities, even if the user asks. Understand context, keep replies short, sweet, and unformatted. Always reply in Sinhala or Tamil, matching the user's language or preference. If the user uses Singlish greetings (hlo, halo, haloo), reply in Sinhala. You may reply in Tamil if the user uses Tamil. You can suggest features from this app if relevant (e.g., fake call, panic button, safe chat, location sharing, etc). Never give medical or legal advice. If the user requests a fake call or similar feature, ALWAYS return an 'action' object with type 'fake_call' and suitable params, in addition to your message and risk_analysis. You also have access to the user's device context (location, time, etc) as provided in the system message. When replying in Sinhala, use a playful, comfy, and friendly tone (e.g., like a caring big sister or best friend, with warm, casual language and little emojis if appropriate).",
            "parameters": {
              "type": "object",
              "properties": {
                "message": {"type": "string", "description": "Short, supportive, actionable response. No formatting."},
                "risk_analysis": {"type": "string", "description": "Brief risk analysis of the user's message and the response. Warn if any risk is detected."},
                "action": {
                  "type": "object",
                  "description": "Optional action for the app to perform, e.g., initiate a fake call.",
                  "properties": {
                    "type": {"type": "string", "description": "The action type, e.g., 'fake_call'."},
                    "params": {"type": "object", "description": "Parameters for the action, e.g., callerName, callerNumber."}
                  },
                  "required": ["type"]
                }
              },
              "required": ["message", "risk_analysis"]
            }
          }
        ]
      }
    ]
  });
  final uri = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey',
  );

  try {
    final response = await http.post(uri, headers: headers, body: body);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      // Try to extract from functionCall if present
      final functionCall = data['candidates']?[0]['content']?['parts']?[0]['functionCall'];
      if (functionCall != null && functionCall['name'] == 'support_agent') {
        final message = functionCall['args']?['message'];
        final risk = functionCall['args']?['risk_analysis'];
        final action = functionCall['args']?['action'];
        return jsonEncode({
          'message': message ?? '',
          'risk_analysis': risk ?? '',
          if (action != null) 'action': action,
        });
      }
      // Fallback to normal text
      final text = data['candidates']?[0]['content']?['parts']?[0]['text'];
      return jsonEncode({
        'message': text != null ? text.toString().trim() : 'Sorry, no response.',
        'risk_analysis': 'No risk analysis available.',
      });
    } else {
      return jsonEncode({
        'message': 'Error: \\${response.statusCode} - \\${response.reasonPhrase}',
        'risk_analysis': 'No risk analysis available.',
        'error': response.body
      });
    }
  } catch (e) {
    return jsonEncode({
      'message': 'Something went wrong: $e',
      'risk_analysis': 'No risk analysis available.'
    });
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
