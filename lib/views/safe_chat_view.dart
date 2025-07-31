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

class _SafeChatViewState extends State<SafeChatView> with TickerProviderStateMixin {
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

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    
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

  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    
    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    super.dispose();
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

  String getAgentPrompt(String mode, String language) {
    String modePrompt = mode == 'yonali' ? AgentPrompts.modeYonali : AgentPrompts.modeSafe;
    String langPrompt = '';
    
    switch (language) {
      case 'auto':
        langPrompt = AgentPrompts.langAuto;
        break;
      case 'sinhala':
        langPrompt = AgentPrompts.langSinhala;
        break;
      case 'english':
        langPrompt = AgentPrompts.langEnglish;
        break;
      case 'singlish':
        langPrompt = AgentPrompts.langSinglish;
        break;
      default:
        langPrompt = AgentPrompts.langAuto;
    }
    
    return modePrompt + '\n\n' + langPrompt;
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
    final timeString = '${now.hour}:${now.minute.toString().padLeft(2, '0')}';
    final dateString = '${now.day}/${now.month}/${now.year}';

    final contextString = '''
Device Context:
- Time: $timeString
- Date: $dateString
- Location: $locationString
- Language: $_defaultLanguage
- Mode: $_mode
''';

    final fullPrompt = contextString + '\n\nUser Message: ' + prompt;

    try {
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [{
              'text': getAgentPrompt(_mode, _defaultLanguage) + '\n\n' + fullPrompt
            }]
          }]
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List;
        if (candidates.isNotEmpty) {
          final content = candidates[0]['content'];
          final parts = content['parts'] as List;
          if (parts.isNotEmpty) {
            return parts[0]['text'] as String;
          }
        }
      }
      return jsonEncode({
        'message': 'Sorry, I could not process your request. Please try again.',
        'risk_analysis': 'Unable to analyze risk due to API error.'
      });
    } catch (e) {
      debugPrint('Error calling Gemini API: $e');
      return jsonEncode({
        'message': 'Sorry, I encountered an error. Please check your internet connection and try again.',
        'risk_analysis': 'Unable to analyze risk due to network error.'
      });
    }
  }

  Future<void> _showSettingsDialog() async {
    final controller = TextEditingController(text: _botNickname);
    String tempMode = _mode;
    String tempLang = _defaultLanguage;
    bool tempShowRisk = _showRiskAnalysis;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Chat Settings', style: GoogleFonts.lato(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Assistant Name',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: tempMode,
              decoration: InputDecoration(
                labelText: 'Mode',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: const [
                DropdownMenuItem(value: 'safe', child: Text('Safe Mode')),
                DropdownMenuItem(value: 'yonali', child: Text('Yonali Mode')),
              ],
              onChanged: (v) => setState(() => tempMode = v!),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: tempLang,
              decoration: InputDecoration(
                labelText: 'Language',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: const [
                DropdownMenuItem(value: 'auto', child: Text('Auto')),
                DropdownMenuItem(value: 'sinhala', child: Text('Sinhala')),
                DropdownMenuItem(value: 'english', child: Text('English')),
                DropdownMenuItem(value: 'singlish', child: Text('Singlish')),
              ],
              onChanged: (v) => setState(() => tempLang = v!),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Switch(
                  value: tempShowRisk,
                  onChanged: (v) => setState(() => tempShowRisk = v),
                  activeColor: const Color(0xFF8F5FE8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Show risk analysis in replies', style: GoogleFonts.lato(fontSize: 15)),
                ),
              ],
            ),
          ],
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
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FF),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF8F5FE8).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8F5FE8)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Loading chat...',
                style: GoogleFonts.lato(
                  fontSize: 16,
                  color: const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // Show chat selection screen if no chat is active (no chatId, no initialMessage)
    if (_chatId == null && widget.initialMessage == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F9FF),
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // Modern App Bar
                SliverAppBar(
                  expandedHeight: 120,
                  floating: false,
                  pinned: true,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF8F5FE8),
                            Color(0xFF667eea),
                          ],
                        ),
                      ),
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.of(context).maybePop(),
                                icon: const Icon(
                                  Icons.arrow_back_ios,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'SafeChat',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    Text(
                                      'AI-powered safety assistant',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Content
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Welcome Section
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8F5FE8), Color(0xFF667eea)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF8F5FE8).withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.shield_rounded,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Your Safety Assistant',
                                style: GoogleFonts.lato(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Get instant help and guidance for any safety concerns',
                                style: GoogleFonts.lato(
                                  fontSize: 16,
                                  color: Colors.white70,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        
                        // Chat History
                        _buildChatHistory(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8F5FE8), Color(0xFF667eea)],
            ),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8F5FE8).withOpacity(0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: FloatingActionButton.extended(
            backgroundColor: Colors.transparent,
            elevation: 0,
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text(
              'New Chat',
              style: GoogleFonts.lato(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
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
        ),
      );
    }
    
    // Main Chat Interface
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FF),
      body: Stack(
        children: [
          // Background
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF8F5FE8),
                  Color(0xFFE9E4F6),
                  Color(0xFFF8F9FF),
                ],
              ),
            ),
          ),
          
          // Chat Content
          Column(
            children: [
              // Modern App Bar
              _buildModernAppBar(),
              
              // Messages
              Expanded(
                child: _buildMessagesList(),
              ),
              
              // Input Bar
              _buildModernInputBar(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernAppBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8F5FE8), Color(0xFF667eea)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8F5FE8).withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(
                  Icons.arrow_back_ios,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              
              // Bot Avatar
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              
              // Bot Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _botNickname,
                      style: GoogleFonts.lato(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withOpacity(0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Online',
                          style: GoogleFonts.lato(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Settings Button
              IconButton(
                onPressed: _showSettingsDialog,
                icon: const Icon(
                  Icons.more_vert,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0 && _loading) {
          return _buildTypingIndicator();
        }
        final messageIndex = _loading ? index - 1 : index;
        final message = _messages[messageIndex];
        final isUser = message['role'] == 'user';
        return _buildMessageBubble(message, isUser);
      },
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message, bool isUser) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shield_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
            const SizedBox(width: 8),
          ],
          
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isUser 
                    ? const Color(0xFF8F5FE8)
                    : Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: Radius.circular(isUser ? 20 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message['content'] ?? '',
                    style: GoogleFonts.lato(
                      fontSize: 16,
                      color: isUser ? Colors.white : const Color(0xFF1A1A2E),
                      height: 1.4,
                    ),
                  ),
                  if (message['risk_analysis'] != null && message['risk_analysis'].toString().isNotEmpty && _showRiskAnalysis) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isUser 
                            ? Colors.white.withOpacity(0.2)
                            : const Color(0xFFFFF3CD),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isUser 
                              ? Colors.white.withOpacity(0.3)
                              : const Color(0xFFFFEAA7),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: isUser ? Colors.white70 : const Color(0xFF856404),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              message['risk_analysis'],
                              style: GoogleFonts.lato(
                                fontSize: 12,
                                color: isUser ? Colors.white70 : const Color(0xFF856404),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          if (isUser) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person,
                color: Colors.white,
                size: 16,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.shield_rounded,
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTypingDot(0),
                const SizedBox(width: 4),
                _buildTypingDot(1),
                const SizedBox(width: 4),
                _buildTypingDot(2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingDot(int index) {
    return AnimatedBuilder(
      animation: _fadeController,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: const Color(0xFF8F5FE8),
            shape: BoxShape.circle,
          ),
        );
      },
    );
  }

  Widget _buildModernInputBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FF),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: const Color(0xFFE5E7EB),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: GoogleFonts.lato(
                      color: const Color(0xFF9CA3AF),
                      fontSize: 16,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                  ),
                  style: GoogleFonts.lato(
                    fontSize: 16,
                    color: const Color(0xFF1A1A2E),
                  ),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (text) {
                    if (text.trim().isNotEmpty) {
                      _sendMessage(text.trim());
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8F5FE8), Color(0xFF667eea)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF8F5FE8).withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () {
                  if (_controller.text.trim().isNotEmpty) {
                    _sendMessage(_controller.text.trim());
                  }
                },
                icon: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 24,
                ),
                iconSize: 24,
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('chats')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8F5FE8)),
            ),
          );
        }
        
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8F5FE8).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline,
                    size: 48,
                    color: const Color(0xFF8F5FE8).withOpacity(0.6),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'No chats yet',
                  style: GoogleFonts.lato(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1A1A2E),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Start your first conversation with your safety assistant',
                  style: GoogleFonts.lato(
                    fontSize: 14,
                    color: const Color(0xFF6B7280),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recent Chats',
              style: GoogleFonts.lato(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 16),
            ...docs.map((doc) => _buildChatCard(doc)).toList(),
          ],
        );
      },
    );
  }

  Widget _buildChatCard(DocumentSnapshot doc) {
    final chatId = doc.id;
    final createdAt = (doc['createdAt'] as Timestamp?)?.toDate();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
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
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF8F5FE8), Color(0xFF667eea)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.chat_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chat Session',
                        style: GoogleFonts.lato(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: const Color(0xFF1A1A2E),
                        ),
                      ),
                      if (createdAt != null)
                        Text(
                          '${createdAt.toLocal()}'.split('.')[0],
                          style: GoogleFonts.lato(
                            fontSize: 12,
                            color: const Color(0xFF6B7280),
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: Color(0xFF8F5FE8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
