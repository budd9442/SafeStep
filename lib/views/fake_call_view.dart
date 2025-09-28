import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'dart:io' show Platform;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';

class FakeCallView extends StatefulWidget {
  const FakeCallView({super.key});
  @override
  State<FakeCallView> createState() => _FakeCallViewState();
}

class _FakeCallViewState extends State<FakeCallView> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  String _callerName = 'Unknown';
  String _callerNumber = '';
  String? _selectedRecording;
  bool _isCalling = false;
  AudioPlayer? _audioPlayer;
  String _ringtoneAsset = 'assets/fake_call/ringtone.mp3';
  bool _isRinging = false;
  bool _showInCallUI = false;
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final List<Map<String, String>> _recordings = [
    {'label': 'No Recording', 'asset': ''},
    {'label': 'Random Male', 'asset': 'assets/male_voice.mp3'},
    {'label': 'Random Female', 'asset': 'assets/female_voice.mp3'},
  ];

  final List<Map<String, dynamic>> _templates = [
    {
      'label': 'Brother',
      'callerName': 'Brother',
      'callerNumber': '',
      'asset': 'assets/music.mp3',
      'icon': Icons.person,
      'color': Color(0xFFf5576c),
    },
    {
      'label': 'Dad',
      'callerName': 'Dad',
      'callerNumber': '',
      'asset': 'assets/male_voice.mp3',
      'icon': Icons.person,
      'color': Color(0xFF667eea),
    },
    {
      'label': 'Mom',
      'callerName': 'Mom',
      'callerNumber': '+1 555-987-6543',
      'asset': 'assets/female_voice.mp3',
      'icon': Icons.person,
      'color': Color(0xFFfa709a),
    },
    {
      'label': 'Friend',
      'callerName': 'Unknown',
      'callerNumber': '',
      'asset': '',
      'icon': Icons.person,
      'color': Color(0xFF43e97b),
    },
  ];

  static const _prefsChannel = MethodChannel('com.example.safestep/prefs');

  @override
  void initState() {
    super.initState();
    _setupCallkitListeners();
    _initAudioSession();
    _initAnimations();
  }

  void _initAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _audioPlayer?.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  }

  void _setupCallkitListeners() {
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event == null) return;
      final eventName = event.event.toString();
      if (eventName == 'ACTION_CALL_ACCEPT') {
        _showInCallOverlay();
        if (_selectedRecording != null && _selectedRecording!.isNotEmpty) {
          await _playRecording();
        }
      } else if (eventName == 'ACTION_CALL_DECLINE' || eventName == 'ACTION_CALL_ENDED') {
        _stopRecording();
        _removeInCallOverlay();
      }
    });
  }

  OverlayEntry? _inCallOverlayEntry;

  void _showInCallOverlay() {
    if (_inCallOverlayEntry != null) return;
    _inCallOverlayEntry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: Material(
          color: Colors.black.withOpacity(0.95),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.8),
                  Colors.black.withOpacity(0.95),
                ],
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Call status indicator
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.green, width: 2),
                    ),
                    child: const Icon(
                      Icons.call,
                      color: Colors.green,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Caller info
                  Text(
                    _callerName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (_callerNumber.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      _callerNumber,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.withOpacity(0.5)),
                    ),
                    child: const Text(
                      'In Call...',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // End call button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withOpacity(0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: IconButton(
                      onPressed: () {
                        _stopRecording();
                        FlutterCallkitIncoming.endAllCalls();
                        _removeInCallOverlay();
                      },
                      icon: const Icon(
                        Icons.call_end,
                        color: Colors.white,
                        size: 32,
                      ),
                      iconSize: 32,
                      padding: const EdgeInsets.all(20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_inCallOverlayEntry!);
  }

  void _removeInCallOverlay() {
    _inCallOverlayEntry?.remove();
    _inCallOverlayEntry = null;
  }

  Future<String> _copyAssetToCache(String assetPath) async {
    final byteData = await rootBundle.load(assetPath);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${assetPath.split('/').last}');
    await file.writeAsBytes(byteData.buffer.asUint8List());
    return file.path;
  }

  Future<void> triggerFakeCallSystem({required String callerName, required String callerNumber, required String audioAsset}) async {
    const platform = MethodChannel('com.example.safestep/fakecall');
    String? audioPath;
    if (audioAsset.isNotEmpty) {
      audioPath = await _copyAssetToCache(audioAsset);
    }
    await platform.invokeMethod('triggerFakeCall', {
      'callerName': callerName,
      'callerNumber': callerNumber,
      'audioPath': audioPath ?? '',
    });
  }

  Future<void> _ensurePhoneNumberPermission() async {
    final status = await Permission.phone.status;
    if (!status.isGranted) {
      await Permission.phone.request();
    }
  }

  Future<void> _saveFakeCallPrefs() async {
    await _prefsChannel.invokeMethod('saveFakeCallPrefs', {
      'callerName': _callerName,
      'callerNumber': _callerNumber,
      'audioAsset': _selectedRecording ?? '',
    });
  }

  void _simulateCall() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    await _saveFakeCallPrefs();
    setState(() => _isCalling = true);
    if (Platform.isAndroid) {
      await _ensurePhoneNumberPermission();
      debugPrint('SimulateCall: _selectedRecording=$_selectedRecording');
      final audioAsset = _selectedRecording ?? '';
      if (audioAsset.isNotEmpty) {
        final audioPath = await _copyAssetToCache(audioAsset);
        debugPrint('SimulateCall: audioPath=$audioPath');
        await triggerFakeCallSystem(
          callerName: _callerName,
          callerNumber: _callerNumber.isEmpty ? '1234567890' : _callerNumber,
          audioAsset: audioAsset,
        );
      } else {
        await triggerFakeCallSystem(
          callerName: _callerName,
          callerNumber: _callerNumber.isEmpty ? '1234567890' : _callerNumber,
          audioAsset: '',
        );
      }
    } else {
      _showFakeCallDialog();
    }
    setState(() => _isCalling = false);
  }

  void _showFakeCallDialog() async {
    setState(() => _isCalling = true);
    _isRinging = true;
    _audioPlayer?.dispose();
    _audioPlayer = AudioPlayer();
    await _audioPlayer!.setLoopMode(LoopMode.one);
    await _audioPlayer!.setAsset(_ringtoneAsset);
    await _audioPlayer!.play();
    await Future.delayed(const Duration(seconds: 3));
    if (!_isRinging) return;
    _audioPlayer?.stop();
    _isRinging = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _playRecording();
        return StatefulBuilder(
          builder: (context, setStateDialog) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    const Color(0xFFF8F9FF),
                  ],
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Caller info
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8F5FE8).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8F5FE8),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.call,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _callerName,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A1A2E),
                                ),
                              ),
                              if (_callerNumber.isNotEmpty)
                                Text(
                                  _callerNumber,
                                  style: const TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontSize: 14,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Status
                  if (_selectedRecording != null && _selectedRecording!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8F5FE8).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.volume_up,
                            color: Color(0xFF8F5FE8),
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Playing recording...',
                            style: TextStyle(
                              color: Color(0xFF8F5FE8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'No audio. Just a fake call.',
                        style: TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  const SizedBox(height: 24),
                  
                  // Dismiss button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        _stopRecording();
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8F5FE8),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Dismiss',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    setState(() => _isCalling = false);
  }

  Future<void> _playRecording() async {
    if (_selectedRecording != null && _selectedRecording!.isNotEmpty) {
      _audioPlayer?.dispose();
      _audioPlayer = AudioPlayer();
      await _audioPlayer!.setAsset(_selectedRecording!);
      await _audioPlayer!.play();
    }
  }

  void _stopRecording() {
    _isRinging = false;
    _audioPlayer?.stop();
  }

  void _applyTemplate(Map<String, dynamic> template) {
    setState(() {
      _callerName = template['callerName'] ?? 'Unknown';
      _callerNumber = template['callerNumber'] ?? '';
      _selectedRecording = template['asset'] ?? '';
    });
    _saveFakeCallPrefs();
  }

  @override
  Widget build(BuildContext context) {
    if (_showInCallUI) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.8),
                Colors.black.withOpacity(0.95),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                  child: const Icon(
                    Icons.call,
                    color: Colors.green,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  _callerName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
                if (_callerNumber.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _callerNumber,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.green.withOpacity(0.5)),
                  ),
                  child: const Text(
                    'In Call...',
                    style: TextStyle(
                      color: Colors.green,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 48),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: IconButton(
                    onPressed: () {
                      _stopRecording();
                      setState(() => _showInCallUI = false);
                      FlutterCallkitIncoming.endAllCalls();
                    },
                    icon: const Icon(
                      Icons.call_end,
                      color: Colors.white,
                      size: 32,
                    ),
                    iconSize: 32,
                    padding: const EdgeInsets.all(20),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          // Modern gradient background
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
          
          // Content
          Column(
            children: [
              // Modern App Bar
              _buildModernAppBar(),
              
              // Main Content
              Expanded(
                child: Form(
                  key: _formKey,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            // Compact layout - all in one view
                            Expanded(
                              child: Column(
                                children: [
                                  _buildCompactCallerInfo(),
                                  const SizedBox(height: 16),
                                  _buildCompactAudio(),
                                  const SizedBox(height: 16),
                                  _buildCompactTemplates(),
                                  const SizedBox(height: 20),
                                  _buildActionButtons(),
                                ],
                              ),
                            ),
                            
                            if (_isCalling) _buildCallingStatusCard(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModernAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 24,
        right: 24,
        bottom: 16,
      ),
      child: Row(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fake Call',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Text(
                  'Simulate incoming calls for safety',
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
    );
  }

  Widget _buildCompactCallerInfo() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8F5FE8).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.person,
                    color: Color(0xFF8F5FE8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Caller Information',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF232946),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildCompactTextField(
                    label: 'Name',
                    initialValue: _callerName,
                    onChanged: (val) => setState(() => _callerName = val),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCompactTextField(
                    label: 'Number',
                    initialValue: _callerNumber,
                    keyboardType: TextInputType.phone,
                    onChanged: (val) => setState(() => _callerNumber = val),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactAudio() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8F5FE8).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.audiotrack,
                    color: Color(0xFF8F5FE8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Audio Recording',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF232946),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildCompactDropdown(),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactTemplates() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8F5FE8).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.category,
                    color: Color(0xFF8F5FE8),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Quick Templates',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF232946),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildCompactTemplatesGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [Color(0xFF8F5FE8), Color(0xFF667eea)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8F5FE8).withOpacity(0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: _isCalling ? null : () => triggerFakeCallSystem(
                  callerName: _callerName,
                  callerNumber: _callerNumber,
                  audioAsset: _selectedRecording ?? '',
                ),
                child: Center(
                  child: _isCalling
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Simulate Fake Call',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCallingStatusCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.green, width: 2),
              ),
              child: const Icon(
                Icons.call,
                color: Colors.green,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Calling...',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF232946),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF8F5FE8).withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF8F5FE8),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1A1A2E),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactTemplatesGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.0,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _templates.length,
      itemBuilder: (context, index) {
        final template = _templates[index];
        return _CompactTemplateCard(
          template: template,
          onTap: () => _applyTemplate(template),
        );
      },
    );
  }

  Widget _buildCustomCallForm() {
    return Container(
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
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Caller Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1A1A2E),
              ),
            ),
            const SizedBox(height: 20),
            
            // Caller Name Field
            _buildCompactTextField(
              label: 'Caller Name',
              initialValue: _callerName,
              onChanged: (val) => setState(() => _callerName = val),
            ),
            const SizedBox(height: 16),
            
            // Caller Number Field
            _buildCompactTextField(
              label: 'Caller Number',
              initialValue: _callerNumber,
              keyboardType: TextInputType.phone,
              onChanged: (val) => setState(() => _callerNumber = val),
            ),
            const SizedBox(height: 16),
            
            // Recording Dropdown
            _buildCompactDropdown(),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactTextField({
    required String label,
    required String initialValue,
    TextInputType? keyboardType,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: initialValue,
          keyboardType: keyboardType,
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF8F5FE8), width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedRecording ?? _recordings[0]['asset'],
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF8F5FE8), width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      style: const TextStyle(fontSize: 14),
      items: _recordings
          .map((rec) => DropdownMenuItem<String>(
                value: rec['asset'],
                child: Text(rec['label']!),
              ))
          .toList(),
      onChanged: (val) => setState(() => _selectedRecording = val),
    );
  }

}

class _CompactTemplateCard extends StatelessWidget {
  final Map<String, dynamic> template;
  final VoidCallback onTap;

  const _CompactTemplateCard({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            template['color'] as Color,
            (template['color'] as Color).withOpacity(0.8),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: (template['color'] as Color).withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  template['icon'] as IconData,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  template['label']!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
