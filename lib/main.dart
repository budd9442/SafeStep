// import 'package:flutter/material.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:safestep/home_screen.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:safestep/services/sos_navigation_service.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'services/local_session.dart';
// import 'views/auth/phone_auth_screen.dart';


// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();
//   await Firebase.initializeApp();
//   await dotenv.load();
//   SosNavigationService.initialize();
//   // Request notification permission on Android 13+
//   try {
//     await Permission.notification.request();
//   } catch (_) {}
  
//   // Debug: Check if required environment variables are loaded
//   final geminiApiKey = dotenv.env['GEMINI_API_KEY'];
//   if (geminiApiKey == null || geminiApiKey.isEmpty) {
//     debugPrint('⚠️  WARNING: GEMINI_API_KEY is not set in .env file');
//     debugPrint('⚠️  AI agent functionality will not work without this key');
//     debugPrint('⚠️  Please create a .env file with your Gemini API key');
//     debugPrint('⚠️  See SETUP.md for detailed instructions');
//   } else if (geminiApiKey == 'your_gemini_api_key_here' || geminiApiKey.contains('your_')) {
//     debugPrint('⚠️  WARNING: GEMINI_API_KEY appears to be a placeholder');
//     debugPrint('⚠️  Please replace with your actual Gemini API key');
//   } else {
//     debugPrint('✅ GEMINI_API_KEY loaded successfully');
//   }
  
//   runApp(const MyApp());
// }

// class MyApp extends StatelessWidget {
//   const MyApp({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'SafeStep',
//       theme: ThemeData(
//         primarySwatch: Colors.deepPurple,
//       ),
//       navigatorKey: SosNavigationService.navigatorKey,
//       home: AuthGate(),
//     );
//   }
// }

// class AuthGate extends StatefulWidget {
//   @override
//   State<AuthGate> createState() => _AuthGateState();
// }

// class _AuthGateState extends State<AuthGate> {
//   bool _isLoading = true;
//   bool _isAuthenticated = false;

//   @override
//   void initState() {
//     super.initState();
//     _checkAuthenticationStatus();
//   }

//   Future<void> _checkAuthenticationStatus() async {
//     try {
//       print('🔍 Checking authentication status...');
//       final localUserId = await LocalSession.getCurrentUserId();
//       if (mounted) {
//         if (localUserId != null && localUserId.isNotEmpty) {
//           print('✅ Local session found for $localUserId');
//           _isAuthenticated = true;
//         } else {
//           print('❌ No local session');
//           _isAuthenticated = false;
//         }
//         _isLoading = false;
//         setState(() {});
//       }
//     } catch (e) {
//       print('❌ Error checking authentication status: $e');
//       if (mounted) {
//         setState(() {
//           _isAuthenticated = false;
//           _isLoading = false;
//         });
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (_isLoading) {
//       return const Scaffold(body: Center(child: CircularProgressIndicator()));
//     }
    
//     if (_isAuthenticated) {
//       return const HomeScreen();
//     } else {
//       return PhoneAuthScreen(
//         onAuthSuccess: () {
//           print('🔄 PhoneAuthScreen onAuthSuccess called');
//           // Refresh authentication status after successful login
//           _checkAuthenticationStatus();
//         },
//       );
//     }
//   }
// }

// class MyHomePage extends StatefulWidget {
//   const MyHomePage({super.key, required this.title});

//   // This widget is the home page of your application. It is stateful, meaning
//   // that it has a State object (defined below) that contains fields that affect
//   // how it looks.

//   // This class is the configuration for the state. It holds the values (in this
//   // case the title) provided by the parent (in this case the App widget) and
//   // used by the build method of the State. Fields in a Widget subclass are
//   // always marked "final".

//   final String title;

//   @override
//   State<MyHomePage> createState() => _MyHomePageState();
// }

// class _MyHomePageState extends State<MyHomePage> {
//   int _counter = 0;

//   void _incrementCounter() {
//     setState(() {
//       // This call to setState tells the Flutter framework that something has
//       // changed in this State, which causes it to rerun the build method below
//       // so that the display can reflect the updated values. If we changed
//       // _counter without calling setState(), then the build method would not be
//       // called again, and so nothing would appear to happen.
//       _counter++;
//     });
//   }

//   @override
//   Widget build(BuildContext context) {
//     // This method is rerun every time setState is called, for instance as done
//     // by the _incrementCounter method above.
//     //
//     // The Flutter framework has been optimized to make rerunning build methods
//     // fast, so that you can just rebuild anything that needs updating rather
//     // than having to individually change instances of widgets.
//     return Scaffold(
//       appBar: AppBar(
//         // TRY THIS: Try changing the color here to a specific color (to
//         // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
//         // change color while the other colors stay the same.
//         backgroundColor: Theme.of(context).colorScheme.inversePrimary,
//         // Here we take the value from the MyHomePage object that was created by
//         // the App.build method, and use it to set our appbar title.
//         title: Text(widget.title),
//       ),
//       body: Center(
//         // Center is a layout widget. It takes a single child and positions it
//         // in the middle of the parent.
//         child: Column(
//           // Column is also a layout widget. It takes a list of children and
//           // arranges them vertically. By default, it sizes itself to fit its
//           // children horizontally, and tries to be as tall as its parent.
//           //
//           // Column has various properties to control how it sizes itself and
//           // how it positions its children. Here we use mainAxisAlignment to
//           // center the children vertically; the main axis here is the vertical
//           // axis because Columns are vertical (the cross axis would be
//           // horizontal).
//           //
//           // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
//           // action in the IDE, or press "p" in the console), to see the
//           // wireframe for each widget.
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: <Widget>[
//             const Text('You have pushed the button this many times:'),
//             Text(
//               '$_counter',
//               style: Theme.of(context).textTheme.headlineMedium,
//             ),
//           ],
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _incrementCounter,
//         tooltip: 'Increment',
//         child: const Icon(Icons.add),
//       ), // This trailing comma makes auto-formatting nicer for build methods.
//     );
//   }
// }
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:safestep/home_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:safestep/services/sos_navigation_service.dart';
import 'package:safestep/services/native_background_location_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await dotenv.load();
  SosNavigationService.initialize();

  // Request notification permission on Android 13+
  try {
    await Permission.notification.request();
  } catch (_) {}

  // Request location permissions
  try {
    await Permission.location.request();
    await Permission.locationAlways.request();
  } catch (_) {}

  // Start native background location service
  try {
    await NativeBackgroundLocationService.initialize();
    await NativeBackgroundLocationService.startTracking();
  } catch (_) {}

  // Debug: Check if required environment variables are loaded
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
      home: const HomeScreen(), // 👈 Skips OTP & goes directly to Home
    );
  }
}
