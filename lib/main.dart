import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:safestep/home_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:safestep/services/sos_navigation_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/local_session.dart';
import 'views/auth/phone_auth_screen.dart';
import 'views/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await dotenv.load();
  SosNavigationService.initialize();
  try {
    await Permission.notification.request();
  } catch (_) {}

  final geminiApiKey = dotenv.env['GEMINI_API_KEY'];
  if (geminiApiKey == null || geminiApiKey.isEmpty) {
    debugPrint('⚠️  WARNING: GEMINI_API_KEY is not set in .env file');
    debugPrint('⚠️  AI agent functionality will not work without this key');
    debugPrint('⚠️  Please create a .env file with your Gemini API key');
    debugPrint('⚠️  See SETUP.md for detailed instructions');
  } else if (geminiApiKey == 'your_gemini_api_key_here' || geminiApiKey.contains('your_')) {
    debugPrint('⚠️  WARNING: GEMINI_API_KEY appears to be a placeholder');
    debugPrint('⚠️  Please replace with your actual Gemini API key');
  } else {
    debugPrint('✅ GEMINI_API_KEY loaded successfully');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SafeStep',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
      ),
      navigatorKey: SosNavigationService.navigatorKey,
      home: SplashToAuthGate(),
    );
  }
}

class SplashToAuthGate extends StatefulWidget {
  @override
  State<SplashToAuthGate> createState() => _SplashToAuthGateState();
}

class _SplashToAuthGateState extends State<SplashToAuthGate> {
  bool _showSplash = true;

  void _finishSplash() {
    setState(() {
      _showSplash = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showSplash) {
      return SplashScreen(onFinish: _finishSplash);
    } else {
      return AuthGate();
    }
  }
}

class AuthGate extends StatefulWidget {
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuthenticationStatus();
  }

  Future<void> _checkAuthenticationStatus() async {
    try {
      print('🔍 Checking authentication status...');
      final localUserId = await LocalSession.getCurrentUserId();
      if (mounted) {
        if (localUserId != null && localUserId.isNotEmpty) {
          print('✅ Local session found for $localUserId');
          _isAuthenticated = true;
        } else {
          print('❌ No local session');
          _isAuthenticated = false;
        }
        _isLoading = false;
        setState(() {});
      }
    } catch (e) {
      print('❌ Error checking authentication status: $e');
      if (mounted) {
        setState(() {
          _isAuthenticated = false;
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isAuthenticated) {
      return const HomeScreen();
    } else {
      return PhoneAuthScreen(
        onAuthSuccess: () {
          print('🔄 PhoneAuthScreen onAuthSuccess called');
          _checkAuthenticationStatus();
        },
      );
    }
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;

  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}