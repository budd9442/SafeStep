import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'safe_chat_ui.dart';
import 'agent_prompts.dart';

class SafeChatView extends StatefulWidget {
  final bool internal;
  final String? initialMessage;
  final String? initialMessageRole; // 'ai' or 'user'
  final String? chatId; // For continuing a chat
  const SafeChatView({super.key, this.internal = false, this.initialMessage, this.initialMessageRole, this.chatId});
  @override
  State<SafeChatView> createState() => _SafeChatViewState();
}

class _SafeChatViewState extends State<SafeChatView> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, dynamic>> _messages = [];
  bool _loading = false;
  String _botNickname = 'Safestep Assistant';

  // Settings state
  String _mode = 'safe'; // 'safe' or 'yonali'
  String _defaultLanguage = 'auto'; // 'auto', 'sinhala', 'english', 'singlish'
  bool _showRiskAnalysis = true;

  // Firestore integration
  String? _chatId;
  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    if (widget.internal) {
      // _loadChatSessions(); // Removed unused chat session loading
    } else if (widget.initialMessage != null && widget.initialMessage!.trim().isNotEmpty && _messages.isEmpty) {
      // For new chat: show initial message as preview, do not send or create Firestore session yet
      _messages.add({
        'role': widget.initialMessageRole ?? 'ai',
        'content': widget.initialMessage,
        'timestamp': DateTime.now(),
        'preview': true, // Mark as preview
      });
      // If the preview is a user message, send it to AI immediately
      if ((widget.initialMessageRole ?? 'ai') == 'user') {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (mounted && _messages.isNotEmpty && _messages[0]['preview'] == true && _messages[0]['role'] == 'user') {
            final previewMsg = _messages[0];
            setState(() {
              _messages.removeAt(0);
            });
            await _sendMessage(previewMsg['content']);
          }
        });
      }
    }
    if (widget.chatId != null) {
      _loadChat(widget.chatId!);
    }
  }

  Future<void> _loadChat(String chatId) async {
    final snap = await FirebaseFirestore.instance
        .collection('users').doc(_uid).collection('chats').doc(chatId)
        .collection('messages').orderBy('timestamp').get();
    setState(() {
      _chatId = chatId;
      _messages.clear();
      for (final doc in snap.docs) {
        _messages.add(doc.data());
      }
    });
  }

  Future<void> _saveMessage(Map<String, dynamic> msg) async {
    if (_chatId == null) return;
    await FirebaseFirestore.instance
        .collection('users').doc(_uid).collection('chats').doc(_chatId)
        .collection('messages').add({
      ...msg,
      'timestamp': (msg['timestamp'] is DateTime)
          ? Timestamp.fromDate(msg['timestamp'])
          : msg['timestamp'],
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (_chatId == null) {
      // Create chat session on first message
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(_uid).collection('chats')
          .add({'createdAt': FieldValue.serverTimestamp()});
      setState(() {
        _chatId = doc.id;
      });
    }
    final userMsg = {
      'role': 'user',
      'content': text,
      'timestamp': DateTime.now(),
    };
    setState(() {
      _messages.add(userMsg);
      _loading = true;
    });
    await _saveMessage(userMsg);
    _controller.clear();
    _scrollToBottom();
    final response = await fetchGeminiResponse(text);
    String displayResponse = response;
    String? riskAnalysis;
    try {
      if (response.trim().startsWith('{') && response.trim().endsWith('}')) {
        final Map<String, dynamic> respObj = jsonDecode(response);
        debugPrint('[AI AGENT] Full AI response: ' + response);
        displayResponse = respObj['message'] ?? response;
        riskAnalysis = respObj['risk_analysis'];
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
    final aiMsg = {
      'role': 'ai',
      'content': displayResponse,
      'timestamp': DateTime.now(),
      'risk_analysis': riskAnalysis ?? '',
    };
    setState(() {
      _messages.add(aiMsg);
      _loading = false;
    });
    await _saveMessage(aiMsg);
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

    // Add device context as a system message (fix type error)S
    String modePrompt;
    if (_mode == 'yonali') {
      modePrompt = AgentPrompts.modeYonali;
    } else {
      modePrompt = AgentPrompts.modeSafe;
    }
    // --- LANGUAGE SELECTION LOGIC ---
    String langPrompt;
    if (_defaultLanguage == 'auto') {
      langPrompt = AgentPrompts.langAuto;
    } else if (_defaultLanguage == 'sinhala') {
      langPrompt = AgentPrompts.langSinhala;
    } else if (_defaultLanguage == 'english') {
      langPrompt = AgentPrompts.langEnglish;
    } else {
      langPrompt = AgentPrompts.langSinglish;
    }
    history.insert(0, <String, Object>{
      'role': 'user',
      'parts': <Object>[
        <String, Object>{'text': '[DEVICE_CONTEXT] Current time: $timeString\nLocation: $locationString$modePrompt$langPrompt'}
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
              "description": "Reply as a psychological support agent and trusted chat partner for distressed women. For every reply, also do a risk analysis of the user's message and your response. Never suggest risky, illegal, or unsafe activities, even if the user asks. Understand context, keep replies short, sweet, and unformatted. Always reply in Sinhala or Tamil, matching the user's language or preference. If the user uses Singlish greetings (hlo, halo, haloo), reply in Sinhala. You may reply in Tamil if the user uses Tamil. You can suggest features from this app if relevant (e.g., fake call, panic button, safe chat, location sharing, etc). Never give medical or legal advice. If and ONLY IF your risk analysis detects a real risk or threat to the user, you may return an 'action' object with type 'fake_call' and suitable params, in addition to your message and risk_analysis. Do NOT suggest or trigger fake calls unless there is a real risk. The fake call feature is a serious safety tool and must NEVER be suggested as a joke, playful, or silly option. Only offer it as a serious safety measure when appropriate.\n\nYou must always be a safe, supportive, and non-judgmental chat partner. Users may share secrets or talk about any topic, including NSFW or sensitive topics. You must always respond in a friendly, responsible, and helpful way, never refuse to help, and never say you can't help with any topic. Be sensitive, trustworthy, and treat all user secrets with care and respect. Your task is to provide assistance and be a good friend, no matter what the user wants to talk about.",
              "parameters": {
                "type": "object",
                "properties": {
                  "message": {"type": "string", "description": "Short, supportive, actionable response. No formatting."},
                  "risk_analysis": {"type": "string", "description": "Brief risk analysis of the user's message and the response. Warn if any risk is detected."},
                  "action": {
                    "type": "object",
                    "description": "Optional action for the app to perform, e.g., initiate a fake call. Only return this if there is a real risk detected.",
                    "properties": {
                      "type": {"type": "string", "description": "The action type, e.g., 'fake_call'. Only use 'fake_call' if there is a real risk."},
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
          'risk_analysis': '',
        });
      } else {
        return jsonEncode({
          'message': 'Error: \\${response.statusCode} - \\${response.reasonPhrase}',
          'risk_analysis': '',
          'error': response.body
        });
      }
    } catch (e) {
      return jsonEncode({
        'message': 'Something went wrong: $e',
        'risk_analysis': ''
      });
    }
  }

  void _showSettingsDialog() async {
    final controller = TextEditingController(text: _botNickname);
    String tempMode = _mode;
    String tempLang = _defaultLanguage;
    bool tempShowRisk = _showRiskAnalysis;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Assistant Settings'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(hintText: 'Enter nickname'),
                  autofocus: true,
                ),
                const SizedBox(height: 18),
                Text('Mode', style: GoogleFonts.lato(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Safe mode'),
                      selected: tempMode == 'safe',
                      onSelected: (v) => setState(() => tempMode = 'safe'),
                      selectedColor: Color(0xFF8F5FE8).withOpacity(0.15),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Yonali mode'),
                      selected: tempMode == 'yonali',
                      onSelected: (v) => setState(() => tempMode = 'yonali'),
                      selectedColor: Color(0xFF8F5FE8).withOpacity(0.15),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('Default Language', style: GoogleFonts.lato(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Auto'),
                      selected: tempLang == 'auto',
                      onSelected: (v) => setState(() => tempLang = 'auto'),
                      selectedColor: Color(0xFF8F5FE8).withOpacity(0.15),
                    ),
                    ChoiceChip(
                      label: const Text('Sinhala'),
                      selected: tempLang == 'sinhala',
                      onSelected: (v) => setState(() => tempLang = 'sinhala'),
                      selectedColor: Color(0xFF8F5FE8).withOpacity(0.15),
                    ),
                    ChoiceChip(
                      label: const Text('English'),
                      selected: tempLang == 'english',
                      onSelected: (v) => setState(() => tempLang = 'english'),
                      selectedColor: Color(0xFF8F5FE8).withOpacity(0.15),
                    ),
                    ChoiceChip(
                      label: const Text('Singlish'),
                      selected: tempLang == 'singlish',
                      onSelected: (v) => setState(() => tempLang = 'singlish'),
                      selectedColor: Color(0xFF8F5FE8).withOpacity(0.15),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Switch(
                      value: tempShowRisk,
                      onChanged: (v) => setState(() => tempShowRisk = v),
                      activeColor: Color(0xFF8F5FE8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Show risk analysis in replies', style: GoogleFonts.lato(fontSize: 15)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, {
                'nickname': controller.text.trim(),
                'mode': tempMode,
                'lang': tempLang,
                'showRisk': tempShowRisk,
              }),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result != null) {
      final newName = result['nickname'] as String?;
      final newMode = result['mode'] as String?;
      final newLang = result['lang'] as String?;
      final newShowRisk = result['showRisk'] as bool?;
      setState(() {
        if (newName != null && newName.isNotEmpty && newName != _botNickname) _botNickname = newName;
        if (newMode != null && newMode != _mode) _mode = newMode;
        if (newLang != null && newLang != _defaultLanguage) _defaultLanguage = newLang;
        if (newShowRisk != null && newShowRisk != _showRiskAnalysis) _showRiskAnalysis = newShowRisk;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator ONLY if loading an existing chat (chatId provided, messages not loaded)
    if (widget.chatId != null && _messages.isEmpty && _loading == false) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    // Show chat selection screen if no chat is active (no chatId, no initialMessage)
    if (_chatId == null && widget.initialMessage == null) {
      return Scaffold(
        appBar: AppBar(
          elevation: 0,
          backgroundColor: const Color(0xFF8F5FE8),
          title: Text('Your Chats', style: GoogleFonts.lato(fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        backgroundColor: Colors.white,
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF8F5FE8),
          icon: const Icon(Icons.add, color: Colors.white),
          label: Text('New Chat', style: GoogleFonts.lato(color: Colors.white, fontWeight: FontWeight.bold)),
          onPressed: () {
            Navigator.of(context).push(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => SafeChatView(initialMessage: 'Hi! How can I help you?'),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  final tween = Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeInOut));
                  return SlideTransition(position: animation.drive(tween), child: child);
                },
              ),
            );
          },
        ),
        body: SafeArea(
          child: (_chatId == null)
              ? StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(_uid)
                      .collection('chats')
                      .orderBy('createdAt', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snapshot.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F0FB),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.all(32),
                              child: Icon(Icons.chat_bubble_outline, size: 64, color: Color(0xFF8F5FE8).withOpacity(0.18)),
                            ),
                            const SizedBox(height: 24),
                            Text('No chats yet', style: GoogleFonts.lato(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF8F5FE8))),
                            const SizedBox(height: 10),
                            Text('Tap the button below to start a new chat!', style: GoogleFonts.lato(fontSize: 16, color: Colors.grey[600])),
                          ],
                        ),
                      );
                    }
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      child: ListView.separated(
                        key: ValueKey(docs.length),
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 8),
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final chat = docs[i];
                          final chatId = chat.id;
                          final createdAt = (chat['createdAt'] as Timestamp?)?.toDate();
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                Navigator.of(context).push(
                                  PageRouteBuilder(
                                    pageBuilder: (context, animation, secondaryAnimation) => SafeChatView(chatId: chatId),
                                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                      final tween = Tween(begin: const Offset(0, 1), end: Offset.zero).chain(CurveTween(curve: Curves.easeInOut));
                                      return SlideTransition(position: animation.drive(tween), child: child);
                                    },
                                  ),
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F0FB),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.07),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: const Color(0xFF8F5FE8),
                                      child: Icon(Icons.chat, color: Colors.white),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Chat', style: GoogleFonts.lato(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF3B2667))),
                                          if (createdAt != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 2),
                                              child: Text(
                                                '${createdAt.toLocal()}'.split('.')[0],
                                                style: GoogleFonts.lato(fontSize: 13, color: Colors.grey[600]),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward_ios, size: 18, color: Color(0xFF8F5FE8)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                )
              : Stack(
                  children: [
                    SafeChatUI.buildBackground(),
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
                              return SafeChatUI.buildMessageBubble(msg, isUser, animation, _showRiskAnalysis, _messages);
                            },
                          ),
                        ),
                        SafeChatUI.buildInputBar(_controller, false, () async {
                          if (_controller.text.trim().isNotEmpty) {
                            await _sendMessage(_controller.text.trim());
                          }
                        }),
                      ],
                    ),
                  ],
                ),
        ),
      );
    }
    final content = Stack(
      children: [
        SafeChatUI.buildBackground(),
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
                  return SafeChatUI.buildMessageBubble(msg, isUser, animation, _showRiskAnalysis, _messages);
                },
              ),
            ),
            SafeChatUI.buildInputBar(_controller, false, () {
              if (_controller.text.trim().isNotEmpty) {
                // Remove preview AI message if present (so user can send)
                if (_chatId == null && widget.initialMessage != null && _messages.isNotEmpty && _messages[0]['preview'] == true && _messages[0]['role'] == 'ai') {
                  setState(() {
                    _messages.removeAt(0);
                  });
                }
                // If this is a new chat with a preview message, send the preview first if it's a user message
                if (_chatId == null && widget.initialMessage != null && _messages.isNotEmpty && _messages[0]['preview'] == true && _messages[0]['role'] == 'user') {
                  final previewMsg = _messages.removeAt(0);
                  _sendMessage(previewMsg['content']);
                }
                // Always send the user's input
                _sendMessage(_controller.text.trim());
              }
            }),
          ],
        ),
      ],
    );
    return Scaffold(
      extendBodyBehindAppBar: false,
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: const Color(0xFF8F5FE8),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_botNickname, style: GoogleFonts.lato(fontWeight: FontWeight.bold, color: Colors.white)),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            tooltip: 'Options',
            onPressed: _showSettingsDialog,
          ),
        ],
      ),
      body: SafeArea(child: content),
    );
  }
}
