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
  final bool internal;
  const FakeCallView({super.key, this.internal = false});
  @override
  State<FakeCallView> createState() => _FakeCallViewState();
}

class _FakeCallViewState extends State<FakeCallView> {
  final _formKey = GlobalKey<FormState>();
  String _callerName = 'Unknown';
  String _callerNumber = '';
  String? _selectedRecording;
  bool _isCalling = false;
  AudioPlayer? _audioPlayer; // just_audio AudioPlayer
  String _ringtoneAsset = 'assets/fake_call/ringtone.mp3'; // Add a default ringtone asset
  bool _isRinging = false;
  bool _showInCallUI = false;

  final List<Map<String, String>> _recordings = [
    {'label': 'No Recording', 'asset': ''},
    {'label': 'Distress Example', 'asset': 'assets/music.mp3'},
    {'label': 'Random Male', 'asset': 'assets/male_voice.mp3'},
    {'label': 'Random Female', 'asset': 'assets/female_voice.mp3'},
  ];

  final List<Map<String, String>> _templates = [
    {
      'label': 'Emergency 119',
      'callerName': 'Emergency Services',
      'callerNumber': '119',
      'asset': 'assets/music.mp3',
    },
    {
      'label': 'Parent',
      'callerName': 'Dad',
      'callerNumber': '',
      'asset': 'assets/male_voice.mp3',
    },
    {
      'label': 'Parent',
      'callerName': 'Mom',
      'callerNumber': '+1 555-987-6543',
      'asset': 'assets/female_voice.mp3',
    },
    {
      'label': 'Friend',
      'callerName': 'Unknown',
      'callerNumber': '',
      'asset': '',
    },
  ];

  @override
  void initState() {
    super.initState();
    _setupCallkitListeners();
    _initAudioSession();
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
        // Show a custom overlay UI using a dialog or overlay entry
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
          color: Colors.black.withOpacity(0.85),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.call, color: Colors.greenAccent, size: 64),
                SizedBox(height: 24),
                Text(_callerName, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
                if (_callerNumber.isNotEmpty)
                  Text(_callerNumber, style: TextStyle(color: Colors.white70, fontSize: 18)),
                SizedBox(height: 32),
                Text('In Call...', style: TextStyle(color: Colors.greenAccent, fontSize: 20)),
                SizedBox(height: 32),
                ElevatedButton.icon(
                  icon: Icon(Icons.call_end, color: Colors.white),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  onPressed: () {
                    _stopRecording();
                    FlutterCallkitIncoming.endAllCalls();
                    _removeInCallOverlay();
                  },
                  label: Text('End Call', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ),
              ],
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

  @override
  void dispose() {
    _audioPlayer?.dispose();
    super.dispose();
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
      'audioPath': audioPath ?? '', // <-- always use audioPath
    });
  }

  Future<void> _ensurePhoneNumberPermission() async {
    final status = await Permission.phone.status;
    if (!status.isGranted) {
      await Permission.phone.request();
    }
  }

  void _simulateCall() async {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
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
          builder: (context, setStateDialog) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.call, color: Color(0xFF8F5FE8)),
                const SizedBox(width: 8),
                Text(_callerName),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_callerNumber.isNotEmpty)
                  Text(_callerNumber, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                if (_selectedRecording != null && _selectedRecording!.isNotEmpty)
                  Row(
                    children: [
                      const Icon(Icons.volume_up, color: Color(0xFF8F5FE8)),
                      const SizedBox(width: 8),
                      const Text('Playing recording...'),
                    ],
                  ),
                if (_selectedRecording == null || _selectedRecording!.isEmpty)
                  const Text('No audio. Just a fake call.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  _stopRecording();
                  Navigator.pop(ctx);
                },
                child: const Text('Dismiss'),
              ),
            ],
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

  void _applyTemplate(Map<String, String> template) {
    setState(() {
      _callerName = template['callerName'] ?? 'Unknown';
      _callerNumber = template['callerNumber'] ?? '';
      _selectedRecording = template['asset'] ?? '';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showInCallUI) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.call, color: Colors.greenAccent, size: 64),
              SizedBox(height: 24),
              Text(_callerName, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              if (_callerNumber.isNotEmpty)
                Text(_callerNumber, style: TextStyle(color: Colors.white70, fontSize: 18)),
              SizedBox(height: 32),
              Text('In Call...', style: TextStyle(color: Colors.greenAccent, fontSize: 20)),
              SizedBox(height: 32),
              ElevatedButton.icon(
                icon: Icon(Icons.call_end, color: Colors.white),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: () {
                  _stopRecording();
                  setState(() => _showInCallUI = false);
                  FlutterCallkitIncoming.endAllCalls();
                },
                label: Text('End Call', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ],
          ),
        ),
      );
    }
    final content = SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              color: const Color(0xFFF6F4FF),
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Templates', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _templates.map((tpl) => ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8F5FE8),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        ),
                        onPressed: () => _applyTemplate(tpl),
                        child: Text(tpl['label']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                      )).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(18.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Customize Fake Call', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const SizedBox(height: 18),
                      TextFormField(
                        initialValue: _callerName,
                        decoration: const InputDecoration(
                          labelText: 'Caller Name',
                          border: OutlineInputBorder(),
                        ),
                        onSaved: (val) => _callerName = val?.trim().isEmpty ?? true ? 'Unknown' : val!.trim(),
                        onChanged: (val) => setState(() => _callerName = val),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        initialValue: _callerNumber,
                        decoration: const InputDecoration(
                          labelText: 'Caller Number',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        onSaved: (val) => _callerNumber = val?.trim() ?? '',
                        onChanged: (val) => setState(() => _callerNumber = val),
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: _selectedRecording ?? _recordings[0]['asset'],
                        decoration: const InputDecoration(
                          labelText: 'Recording',
                          border: OutlineInputBorder(),
                        ),
                        items: _recordings
                            .map((rec) => DropdownMenuItem<String>(
                                  value: rec['asset'],
                                  child: Text(rec['label']!),
                                ))
                            .toList(),
                        onChanged: (val) => setState(() => _selectedRecording = val),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.call, color: Colors.white),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8F5FE8),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        onPressed: _isCalling ? null : _simulateCall,
                        label: const Text('Simulate Fake Call'),
                      ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.bug_report, color: Colors.white),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        onPressed: _isCalling
                            ? null
                            : () async {
                                // Hardcoded test values for debug
                                setState(() => _isCalling = true);
                                if (Platform.isAndroid) {
                                  await _ensurePhoneNumberPermission();
                                  await triggerFakeCallSystem(
                                    callerName: 'Test Caller',
                                    callerNumber: '5551234567',
                                    audioAsset: '',
                                  );
                                } else {
                                  _showFakeCallDialog();
                                }
                                setState(() => _isCalling = false);
                              },
                        label: const Text('Test Native Fake Call'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (widget.internal) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fake Call'),
        backgroundColor: const Color(0xFF8F5FE8),
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF6F4FF),
      body: content,
    );
  }
}
