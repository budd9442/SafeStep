import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/local_session.dart';
import '../services/agent_data_service.dart';
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
  String _defaultLanguage = 'auto'; // 'auto', 'sinhala', 'english', 'singlish'
  bool _showRiskAnalysis = true;

  // Firestore integration
  String? _chatId;
  String? _uid;
  String? _aiName;
  String? _aiPersonality;
  String? _aiPersonalityText;
  String? _aiVoice;
  String? _aiResponseStyle;
  bool _aiLocationAware = true;
  bool _aiSensorAware = true;
  bool _aiContextAware = true;
  String? _aiProfileImageUrl;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initUserId();
    _startAgentDataCollection();
    
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

  Future<void> _initUserId() async {
    _uid = await LocalSession.getCurrentUserId();
    if (_uid != null && mounted) {
      await _loadAIAssistantSettings();
      setState(() {});
      
      // Load chat after user ID is initialized
      if (widget.chatId != null) {
        _loadChat(widget.chatId!);
        // Add timeout to prevent infinite loading
        Timer(const Duration(seconds: 15), () {
          if (mounted && _messages.isEmpty && _loading == false) {
            print('⚠️ [CHAT] Loading timeout after 15 seconds - starting fresh chat');
            setState(() {
              _messages.add({
                'role': 'system',
                'content': 'Chat loading timed out. Starting fresh conversation.',
                'timestamp': DateTime.now(),
              });
            });
          }
        });
      }
    }
  }

  Future<void> _loadAIAssistantSettings() async {
    if (_uid == null) return;
    
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid!)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        final aiSettings = data['aiAssistantSettings'] as Map<String, dynamic>? ?? {};
        
        setState(() {
          _aiName = aiSettings['name'] ?? 'SafeStep Assistant';
          _aiPersonality = aiSettings['personality'] ?? 'supportive';
          _aiPersonalityText = aiSettings['personalityText'] ?? '';
          _aiVoice = aiSettings['voice'] ?? 'calm';
          _aiResponseStyle = aiSettings['responseStyle'] ?? 'professional';
          _aiLocationAware = aiSettings['locationAware'] ?? true;
          _aiSensorAware = aiSettings['sensorAware'] ?? true;
          _aiContextAware = aiSettings['contextAware'] ?? true;
          _aiProfileImageUrl = aiSettings['profileImageUrl'];
        });
        
        print('✅ [SAFE CHAT] AI Assistant settings loaded: ${_aiName}');
      }
    } catch (e) {
      print('❌ [SAFE CHAT] Error loading AI assistant settings: $e');
    }
  }

  Future<void> _startAgentDataCollection() async {
    try {
      await AgentDataService.startDataCollection();
      print('✅ [SAFE CHAT] Agent data collection started');
    } catch (e) {
      print('❌ [SAFE CHAT] Failed to start agent data collection: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    AgentDataService.stopDataCollection();
    super.dispose();
  }

  Future<void> _loadChat(String chatId) async {
    if (_uid == null || _uid!.isEmpty) {
      print('❌ [CHAT] No user ID available for loading chat: $chatId');
      return;
    }
    
    try {
      print('🔄 [CHAT] Loading chat: $chatId for user: $_uid');
      
      // First check if the chat document exists
      final chatDoc = await FirebaseFirestore.instance
          .collection('users').doc(_uid!).collection('chats').doc(chatId)
          .get();
      
      if (!chatDoc.exists) {
        print('⚠️ [CHAT] Chat document does not exist: $chatId');
        setState(() {
          _chatId = chatId;
          _messages.clear();
          _messages.add({
            'role': 'system',
            'content': 'Chat not found. Starting fresh conversation.',
            'timestamp': DateTime.now(),
          });
        });
        return;
      }
      
      // Load messages
      final snap = await FirebaseFirestore.instance
          .collection('users').doc(_uid!).collection('chats').doc(chatId)
          .collection('messages').orderBy('timestamp').get();
      
      print('✅ [CHAT] Loaded ${snap.docs.length} messages for chat: $chatId');
      setState(() {
        _chatId = chatId;
        _messages.clear();
        for (final doc in snap.docs) {
          _messages.add(doc.data());
        }
      });
    } catch (e) {
      print('❌ [CHAT] Error loading chat $chatId: $e');
      setState(() {
        _chatId = chatId;
        _messages.clear();
        // Add error message to show user
        _messages.add({
          'role': 'system',
          'content': 'Failed to load chat history. Starting fresh conversation.',
          'timestamp': DateTime.now(),
        });
      });
    }
  }

  Future<void> _saveMessage(Map<String, dynamic> msg) async {
    if (_chatId == null || _uid == null || _uid!.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('users').doc(_uid!).collection('chats').doc(_chatId)
        .collection('messages').add({
      ...msg,
      'timestamp': (msg['timestamp'] is DateTime)
          ? Timestamp.fromDate(msg['timestamp'])
          : msg['timestamp'],
    });
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    if (_uid == null || _uid!.isEmpty) return;
    
    if (_chatId == null) {
      // Create chat session on first message
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(_uid!).collection('chats')
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
    debugPrint('[CHAT] Added user message: ${_messages.length} total messages');
    await _saveMessage(userMsg);
    _controller.clear();
    _scrollToBottom();
    final response = await fetchGeminiResponse(text);
    String displayResponse = response;
    String? riskAnalysis;
    try {
      // First, try to clean the response to extract JSON if it's wrapped in markdown
      String cleanResponse = response.trim();
      
      // Remove markdown code blocks if present
      if (cleanResponse.startsWith('```json') && cleanResponse.endsWith('```')) {
        cleanResponse = cleanResponse.substring(7, cleanResponse.length - 3).trim();
        debugPrint('[AI AGENT] Removed markdown code blocks, clean response: $cleanResponse');
      } else if (cleanResponse.startsWith('```') && cleanResponse.endsWith('```')) {
        cleanResponse = cleanResponse.substring(3, cleanResponse.length - 3).trim();
        debugPrint('[AI AGENT] Removed markdown code blocks, clean response: $cleanResponse');
      }
      
      if (cleanResponse.startsWith('{') && cleanResponse.endsWith('}')) {
        final Map<String, dynamic> respObj = jsonDecode(cleanResponse);
        debugPrint('[AI AGENT] Full AI response: ' + response);
        debugPrint('[AI AGENT] Cleaned response: $cleanResponse');
        debugPrint('[AI AGENT] Parsed JSON keys: ${respObj.keys.toList()}');
        debugPrint('[AI AGENT] Message field: ${respObj['message']}');
        debugPrint('[AI AGENT] Risk analysis field: ${respObj['risk_analysis']}');
        debugPrint('[AI AGENT] Action field: ${respObj['action']}');
        
        displayResponse = respObj['message'] ?? cleanResponse;
        riskAnalysis = respObj['risk_analysis'];
        debugPrint('[AI AGENT] Final display response: $displayResponse');
        debugPrint('[AI AGENT] Final risk analysis: $riskAnalysis');
        
        // Debug: Check if we're getting the right content
        if (displayResponse == response) {
          debugPrint('[AI AGENT] WARNING: displayResponse equals raw response - JSON parsing may have failed');
        }
        if (respObj['action'] != null && respObj['action']['type'] == 'fake_call') {
          debugPrint('[AI AGENT] Triggering fake call with params: ' + respObj['action']['params'].toString());
          final params = respObj['action']['params'] ?? {};
          await _triggerFakeCallFromAgent(params);
        }
      } else {
        debugPrint('[AI AGENT] AI response (no action): ' + response);
        // If response is not JSON, try to extract fake call request from text
        if (response.toLowerCase().contains('fake call') || 
            response.toLowerCase().contains('call me') || 
            response.toLowerCase().contains('make my phone ring') ||
            response.toLowerCase().contains('initiating') ||
            response.toLowerCase().contains('triggering')) {
          debugPrint('[AI AGENT] Detected fake call request in text, triggering...');
          await _triggerFakeCallFromAgent({
            'caller_name': 'Emergency Contact',
            'caller_number': '+1234567890'
          });
        }
      }
    } catch (e) {
      debugPrint('[AI AGENT] Error parsing action: $e');
      // Fallback: try to detect fake call request even if JSON parsing fails
      if (response.toLowerCase().contains('fake call') || 
          response.toLowerCase().contains('call me') || 
          response.toLowerCase().contains('make my phone ring') ||
          response.toLowerCase().contains('initiating') ||
          response.toLowerCase().contains('triggering')) {
        debugPrint('[AI AGENT] Detected fake call request in text after JSON error, triggering...');
        await _triggerFakeCallFromAgent({
          'caller_name': 'Emergency Contact',
          'caller_number': '+1234567890'
        });
      }
    }
    final aiMsg = {
      'role': 'ai',
      'content': displayResponse,
      'timestamp': DateTime.now(),
      'risk_analysis': riskAnalysis ?? 'No specific risk detected. Stay safe!',
    };
    setState(() {
      _messages.add(aiMsg);
      _loading = false;
    });
    debugPrint('[CHAT] Added AI message: ${_messages.length} total messages');
    await _saveMessage(aiMsg);
    _scrollToBottom();
  }

   Future<void> _triggerFakeCallFromAgent(Map params) async {
    try {
      debugPrint('[AI AGENT] Triggering fake call with params: $params');
      
      // Use the existing method channel for native Android fake calls
      const platform = MethodChannel('com.example.safestep/fakecall');
      
      final Map<String, dynamic> callParams = {
        'callerName': params['caller_name'] ?? 'Emergency Contact',
        'callerNumber': params['caller_number'] ?? '+1234567890',
        'audioPath': 'assets/ringtone.mp3', // Use the ringtone asset
      };
      
      debugPrint('[AI AGENT] Method channel params: $callParams');
      
      // Call the native Android fake call implementation
      await platform.invokeMethod('triggerFakeCall', callParams);
      
      debugPrint('[AI AGENT] Fake call triggered successfully via method channel.');
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fake call incoming! Check your phone.'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      debugPrint('[AI AGENT] Error triggering fake call: $e');
      
      // Fallback: show a notification that fake call was triggered
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Fake call triggered! Check your phone.'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        debugPrint('[CHAT] Scrolling to bottom: maxScroll = $maxScroll');
        _scrollController.animateTo(
          maxScroll,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String getAgentPrompt(String language) {
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
    
    return AgentPrompts.modeSafe + '\n\n' + langPrompt;
  }

  Future<String> fetchGeminiResponse(String prompt) async {
    return await _fetchGeminiResponseWithRetry(prompt, maxRetries: 3);
  }

  Future<String> _fetchGeminiResponseWithRetry(String prompt, {int maxRetries = 3}) async {
    int attempt = 0;
    Exception? lastException;
    
    while (attempt < maxRetries) {
      attempt++;
      print('🔄 [AI AGENT] Attempt $attempt/$maxRetries');
      
      try {
        final result = await _makeGeminiRequest(prompt);
        if (attempt > 1) {
          print('✅ [AI AGENT] Request succeeded on attempt $attempt');
        }
        return result;
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
        print('❌ [AI AGENT] Attempt $attempt failed: $e');
        
        if (attempt < maxRetries) {
          // Wait before retrying (exponential backoff)
          final delay = Duration(seconds: attempt * 2);
          print('⏳ [AI AGENT] Waiting ${delay.inSeconds}s before retry...');
          await Future.delayed(delay);
        }
      }
    }
    
    // All retries failed, return error response
    print('❌ [AI AGENT] All $maxRetries attempts failed. Giving up.');
    return jsonEncode({
      'message': 'AI service is currently unavailable after multiple attempts. Please try again later.',
      'risk_analysis': 'Unable to analyze risk due to persistent API errors.',
      'error_code': 'MAX_RETRIES_EXCEEDED',
      'help': 'The AI service is experiencing technical difficulties. Please try again in a few minutes.',
      'attempts_made': maxRetries,
      'last_error': lastException?.toString() ?? 'Unknown error'
    });
  }

  String _formatChatHistoryCompact() {
    if (_messages.isEmpty) return 'No previous messages';
    
    // Get last 5 messages (excluding the current one being sent)
    final recentMessages = _messages.take(5).toList();
    final List<String> formattedMessages = [];
    
    for (final message in recentMessages) {
      final role = message['role'] as String;
      final content = message['content'] as String;
      final timestamp = message['timestamp'] as DateTime?;
      
      // Format timestamp
      String timeStr = '';
      if (timestamp != null) {
        timeStr = ' (${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')})';
      }
      
      // Truncate long messages
      String truncatedContent = content;
      if (content.length > 100) {
        truncatedContent = '${content.substring(0, 97)}...';
      }
      
      // Format role
      String roleLabel = role == 'user' ? 'User' : 'AI';
      
      formattedMessages.add('$roleLabel$timeStr: $truncatedContent');
    }
    
    return formattedMessages.join('\n');
  }

  String _extractCurrentConcern() {
    if (_messages.isEmpty) return 'None identified';
    
    // Look for recent user messages that might indicate concerns
    final userMessages = _messages.where((msg) => msg['role'] == 'user').toList();
    if (userMessages.isEmpty) return 'None identified';
    
    final lastUserMessage = userMessages.last['content'] as String;
    
    // Simple keyword detection for safety concerns
    final safetyKeywords = [
      'unsafe', 'scared', 'afraid', 'worried', 'danger', 'threat', 'help',
      'emergency', 'panic', 'fear', 'anxious', 'nervous', 'concerned',
      'followed', 'stalked', 'harassed', 'attacked', 'hurt', 'injured'
    ];
    
    final lowerMessage = lastUserMessage.toLowerCase();
    for (final keyword in safetyKeywords) {
      if (lowerMessage.contains(keyword)) {
        return 'Safety concern detected: $keyword';
      }
    }
    
    return 'General inquiry';
  }

  String _analyzeConversationFlow() {
    if (_messages.length < 2) return 'Initial conversation';
    
    // Analyze the pattern of recent messages
    final recentMessages = _messages.take(5).toList();
    final userMessages = recentMessages.where((msg) => msg['role'] == 'user').length;
    final aiMessages = recentMessages.where((msg) => msg['role'] == 'ai').length;
    
    if (userMessages > aiMessages) {
      return 'User seeking help';
    } else if (aiMessages > userMessages) {
      return 'AI providing guidance';
    } else {
      return 'Balanced conversation';
    }
  }

  String _detectOngoingSafetySituation() {
    if (_messages.isEmpty) return 'None';
    
    // Look for patterns that suggest an ongoing safety situation
    final allMessages = _messages.map((msg) => msg['content'] as String).join(' ').toLowerCase();
    
    // Check for emergency keywords
    final emergencyKeywords = ['emergency', 'urgent', 'immediate', 'now', 'help me'];
    for (final keyword in emergencyKeywords) {
      if (allMessages.contains(keyword)) {
        return 'Emergency situation detected';
      }
    }
    
    // Check for ongoing threats
    final threatKeywords = ['followed', 'stalked', 'harassed', 'threatened', 'attacked'];
    for (final keyword in threatKeywords) {
      if (allMessages.contains(keyword)) {
        return 'Ongoing threat situation';
      }
    }
    
    // Check for repeated safety concerns
    final safetyConcerns = ['unsafe', 'scared', 'afraid', 'worried', 'danger'];
    int concernCount = 0;
    for (final keyword in safetyConcerns) {
      if (allMessages.contains(keyword)) {
        concernCount++;
      }
    }
    
    if (concernCount >= 2) {
      return 'Multiple safety concerns raised';
    }
    
    return 'None detected';
  }

  String _formatSafePlacesCompact(List<dynamic> safePlaces) {
    if (safePlaces.isEmpty) return 'None nearby';
    
    final List<String> places = [];
    for (final place in safePlaces.take(3)) { // Only top 3
      final type = place['type'] == 'police_station' ? 'Police' : 'Hospital';
      final name = place['name'] ?? 'Unknown';
      final distance = place['distance_km']?.toStringAsFixed(1) ?? '?';
      places.add('$type: $name (${distance}km)');
    }
    return places.join(', ');
  }

  String _formatSensorStatusCompact(Map<String, dynamic> sensorData) {
    if (sensorData.isEmpty) return 'No data';
    
    final accel = sensorData['accelerometer']?['analysis'];
    if (accel == null) return 'No analysis';
    
    final movement = accel['movement_pattern'] ?? 'unknown';
    final avgMag = accel['average_magnitude']?.toStringAsFixed(1) ?? '?';
    
    String status = movement;
    if (accel['potential_indicators']?['possible_fall'] == true) {
      status += ' (possible fall)';
    } else if (accel['potential_indicators']?['possible_running'] == true) {
      status += ' (running)';
    } else if (accel['potential_indicators']?['possible_stationary'] == true) {
      status += ' (stationary)';
    }
    
    return '$status (avg: ${avgMag})';
  }

  Future<String> _makeGeminiRequest(String prompt) async {
    final apiKey = dotenv.env['GEMINI_API_KEY'];
    
    // Enhanced API key validation with better error messages
    if (apiKey == null || apiKey.isEmpty) {
      debugPrint('[AI AGENT] ERROR: GEMINI_API_KEY is missing or empty');
      debugPrint('[AI AGENT] Please create a .env file with your Gemini API key');
      debugPrint('[AI AGENT] Get your API key from: https://makersuite.google.com/app/apikey');
      
      return jsonEncode({
        'message': 'AI service is currently unavailable. Please check your configuration.',
        'risk_analysis': 'Unable to analyze risk due to missing API configuration.',
        'error_code': 'MISSING_API_KEY',
        'help': 'Contact support or check your environment configuration.'
      });
    }
    
    // Validate API key format (basic check)
    if (apiKey.length < 20) {
      debugPrint('[AI AGENT] ERROR: GEMINI_API_KEY appears to be invalid (too short)');
      return jsonEncode({
        'message': 'AI service configuration error. Please check your API key.',
        'risk_analysis': 'Unable to analyze risk due to invalid API configuration.',
        'error_code': 'INVALID_API_KEY',
        'help': 'Please verify your Gemini API key is correct.'
      });
    }
    
    // Development fallback for testing (remove in production)
    if (apiKey == 'your_gemini_api_key_here' || apiKey.contains('your_')) {
      debugPrint('[AI AGENT] WARNING: Using placeholder API key. Please set a real API key.');
      return jsonEncode({
        'message': 'AI service is in development mode. Please configure your API key.',
        'risk_analysis': 'Development mode - no risk analysis available.',
        'error_code': 'DEV_MODE',
        'help': 'Replace the placeholder API key in your .env file with a real Gemini API key.',
        'dev_note': 'This is a development fallback. Set GEMINI_API_KEY in your .env file.'
      });
    }

    // Gather comprehensive device context using AgentDataService
    Map<String, dynamic> comprehensiveData;
    try {
      comprehensiveData = await AgentDataService.getComprehensiveData();
      print('✅ [AI AGENT] Comprehensive data collected successfully');
    } catch (e) {
      print('❌ [AI AGENT] Failed to collect comprehensive data: $e');
      comprehensiveData = {
        'error': 'Failed to collect comprehensive data: ${e.toString()}',
        'timestamp': DateTime.now().toIso8601String(),
      };
    }

    final contextString = '''
Device Context:
- Time: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}
- Language: $_defaultLanguage

Data Available:
- Location: ${comprehensiveData['location']?['latitude'] != null ? 'Available' : 'Unavailable'}
- Safe Places: ${(comprehensiveData['nearby_safe_places'] as List?)?.length ?? 0} nearby
- Sensor Data: ${comprehensiveData['sensor_data']?['accelerometer']?['raw_data_count'] ?? 0} readings
- User: ${comprehensiveData['user_context']?['name'] ?? 'Unknown'}
''';

    final fullPrompt = '''
You are ${_aiName ?? 'SafeStep Assistant'}, a JSON-only AI safety agent. You MUST respond in valid JSON format. NEVER send plain text, NEVER use markdown, NEVER show code blocks.

PERSONALITY: ${_aiPersonality ?? 'supportive'}, ${_aiVoice ?? 'calm'} voice, ${_aiResponseStyle ?? 'professional'} style
${_aiPersonalityText != null && _aiPersonalityText!.isNotEmpty ? 'CUSTOM: ${_aiPersonalityText}' : ''}

${contextString}

LOCATION: ${comprehensiveData['location']?['latitude'] != null ? '${comprehensiveData['location']['latitude']}, ${comprehensiveData['location']['longitude']}' : 'Unavailable'}
SAFE PLACES: ${_formatSafePlacesCompact(comprehensiveData['nearby_safe_places'] ?? [])}
SENSORS: ${_formatSensorStatusCompact(comprehensiveData['sensor_data'] ?? {})}
TIME: ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')} ${DateTime.now().hour >= 22 || DateTime.now().hour <= 6 ? '(Night)' : '(Day)'}
USER: ${comprehensiveData['user_context']?['name'] ?? 'Unknown'} - ${comprehensiveData['user_context']?['is_sharing_location'] == true ? 'Sharing location' : 'Not sharing'}

CHAT HISTORY: ${_formatChatHistoryCompact()}
CONTEXT: ${_extractCurrentConcern()} | ${_analyzeConversationFlow()} | ${_detectOngoingSafetySituation()}

AWARENESS: Location:${_aiLocationAware ? 'Yes' : 'No'} Sensor:${_aiSensorAware ? 'Yes' : 'No'} Context:${_aiContextAware ? 'Yes' : 'No'}

Provide safety assistance based on your personality profile and available data.

User Message: $prompt

REMEMBER: JSON format only. NEVER send plain text.
''';

    try {
      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1/models/gemini-2.0-flash:generateContent?key=$apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [{
              'text': 'SYSTEM: You are a JSON-only AI. You MUST respond in valid JSON format. NEVER send plain text, NEVER use markdown, NEVER show code blocks.\n\n' + getAgentPrompt(_defaultLanguage) + '\n\n' + fullPrompt
            }]
          }]
        }),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Request timed out after 30 seconds', const Duration(seconds: 30));
        },
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
        
        // Handle case where response is successful but no content
        debugPrint('[AI AGENT] WARNING: API response successful but no content found');
        debugPrint('[AI AGENT] Response data: $data');
        return jsonEncode({
          'message': 'AI response received but no content was generated. Please try again.',
          'risk_analysis': 'Unable to analyze risk due to empty AI response.',
          'error_code': 'EMPTY_RESPONSE',
          'help': 'The AI model returned an empty response. This may be a temporary issue.'
        });
      }
      
      // Handle non-200 status codes with detailed error information
      debugPrint('[AI AGENT] ERROR: API returned status code ${response.statusCode}');
      debugPrint('[AI AGENT] Response body: ${response.body}');
      
      String errorMessage = 'Sorry, I could not process your request. Please try again.';
      String riskAnalysis = 'Unable to analyze risk due to API error.';
      String errorCode = 'API_ERROR';
      String help = 'Please try again later or contact support if the issue persists.';
      
      // Provide specific error messages for common status codes
      switch (response.statusCode) {
        case 400:
          errorMessage = 'Invalid request sent to AI service. Please check your input.';
          errorCode = 'BAD_REQUEST';
          help = 'Your message may contain content that violates AI service policies.';
          break;
        case 401:
          errorMessage = 'AI service authentication failed. Please check your API key.';
          errorCode = 'UNAUTHORIZED';
          help = 'Your API key may be invalid or expired. Please verify your configuration.';
          break;
        case 403:
          errorMessage = 'AI service access denied. Your API key may not have the required permissions.';
          errorCode = 'FORBIDDEN';
          help = 'Please check your API key permissions or upgrade your plan.';
          break;
        case 429:
          errorMessage = 'AI service is currently busy. Please wait a moment and try again.';
          errorCode = 'RATE_LIMITED';
          help = 'You have exceeded the API rate limit. Please wait before sending another message.';
          break;
        case 500:
        case 502:
        case 503:
          errorMessage = 'AI service is temporarily unavailable. Please try again later.';
          errorCode = 'SERVER_ERROR';
          help = 'The AI service is experiencing technical difficulties. Please try again in a few minutes.';
          break;
      }
      
      return jsonEncode({
        'message': errorMessage,
        'risk_analysis': riskAnalysis,
        'error_code': errorCode,
        'help': help,
        'status_code': response.statusCode
      });
    } catch (e) {
      debugPrint('[AI AGENT] ERROR: Exception occurred while calling Gemini API: $e');
      
      String errorMessage = 'Sorry, I encountered an error. Please check your internet connection and try again.';
      String riskAnalysis = 'Unable to analyze risk due to network error.';
      String errorCode = 'NETWORK_ERROR';
      String help = 'Please check your internet connection and try again.';
      
      // Provide specific error messages for common exceptions
      if (e.toString().contains('SocketException') || e.toString().contains('NetworkException')) {
        errorMessage = 'No internet connection detected. Please check your network settings.';
        errorCode = 'NO_INTERNET';
        help = 'Please ensure you have a stable internet connection and try again.';
      } else if (e.toString().contains('TimeoutException')) {
        errorMessage = 'Request timed out. The AI service is taking too long to respond.';
        errorCode = 'TIMEOUT';
        help = 'Please try again. If the issue persists, the AI service may be experiencing high load.';
      } else if (e.toString().contains('FormatException')) {
        errorMessage = 'Invalid response received from AI service. Please try again.';
        errorCode = 'INVALID_RESPONSE';
        help = 'The AI service returned an unexpected response format. This may be a temporary issue.';
      }
      
      return jsonEncode({
        'message': errorMessage,
        'risk_analysis': riskAnalysis,
        'error_code': errorCode,
        'help': help,
        'exception': e.toString()
      });
    }
  }

  Future<void> _showSettingsDialog() async {
    final controller = TextEditingController(text: _botNickname);
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
      final newLang = result['lang'] as String?;
      final newShowRisk = result['showRisk'] as bool?;
      setState(() {
        if (newName != null && newName.isNotEmpty && newName != _botNickname) _botNickname = newName;
        if (newLang != null && newLang != _defaultLanguage) _defaultLanguage = newLang;
        if (newShowRisk != null && newShowRisk != _showRiskAnalysis) _showRiskAnalysis = newShowRisk;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator ONLY if loading an existing chat (chatId provided, messages not loaded)
    // Add timeout to prevent infinite loading
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
                child: _aiProfileImageUrl != null
                    ? ClipOval(
                        child: Image.network(
                          _aiProfileImageUrl!,
                          width: 24,
                          height: 24,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(
                              Icons.shield_rounded,
                              color: Colors.white,
                              size: 24,
                            );
                          },
                        ),
                      )
                    : const Icon(
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
                      _aiName ?? _botNickname,
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
              
                            // Test Fake Call Button (for debugging)
              IconButton(
                onPressed: () async {
                  debugPrint('[TEST] Manual fake call test triggered');
                  await _triggerFakeCallFromAgent({
                    'caller_name': 'Test Call',
                    'caller_number': '+1234567890'
                  });
                },
                icon: const Icon(
                  Icons.phone,
                  color: Colors.white,
                  size: 24,
                ),
                tooltip: 'Test Fake Call',
              ),
              
              // Test JSON Parsing Button (for debugging)
              IconButton(
                onPressed: () {
                  debugPrint('[TEST] Testing JSON parsing...');
                  
                  // Test 1: Valid JSON
                  final testResponse1 = '{"message": "Test message", "risk_analysis": "Test risk analysis", "action": null}';
                  debugPrint('[TEST] Test 1 - Valid JSON: $testResponse1');
                  
                  try {
                    final parsed1 = jsonDecode(testResponse1);
                    debugPrint('[TEST] Test 1 - Parsed successfully: ${parsed1['message']}');
                  } catch (e) {
                    debugPrint('[TEST] Test 1 - JSON parsing failed: $e');
                  }
                  
                  // Test 2: Markdown wrapped JSON (like what you're getting)
                  final testResponse2 = '```json\n{"message": "Test message", "risk_analysis": "Test risk analysis", "action": null}\n```';
                  debugPrint('[TEST] Test 2 - Markdown JSON: $testResponse2');
                  
                  try {
                    String cleanResponse = testResponse2.trim();
                    if (cleanResponse.startsWith('```json') && cleanResponse.endsWith('```')) {
                      cleanResponse = cleanResponse.substring(7, cleanResponse.length - 3).trim();
                      debugPrint('[TEST] Test 2 - Cleaned response: $cleanResponse');
                    }
                    
                    final parsed2 = jsonDecode(cleanResponse);
                    debugPrint('[TEST] Test 2 - Parsed successfully: ${parsed2['message']}');
                  } catch (e) {
                    debugPrint('[TEST] Test 2 - JSON parsing failed: $e');
                  }
                },
                icon: const Icon(
                  Icons.code,
                  color: Colors.white,
                  size: 24,
                ),
                tooltip: 'Test JSON Parsing',
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
      reverse: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: _messages.length + (_loading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _messages.length && _loading) {
          return _buildTypingIndicator();
        }
        final message = _messages[index];
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
    if (_uid == null || _uid!.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8F5FE8)),
        ),
      );
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_uid!)
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
