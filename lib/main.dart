import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:safestep/home_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:safestep/services/sos_navigation_service.dart';
import 'package:firebase_core/firebase_core.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await dotenv.load();
  SosNavigationService.initialize();
  try {
    await Permission.notification.request();
  } catch (_) {}

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
      home: const HomeScreen(), // 👈 Skip everything & go directly
    );
  }
}
