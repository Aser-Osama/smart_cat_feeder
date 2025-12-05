import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/feeder_provider.dart';
import 'screens/splash_screen.dart';
import 'services/firebase_service.dart';
import 'services/preferences_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize MediaKit for video playback
  MediaKit.ensureInitialized();
  
  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Initialize services (Phase 2)
  await PreferencesService.initialize();
  await FirebaseService.initialize();
  await NotificationService.initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthProvider _authProvider;
  late final FeederProvider _feederProvider;
  
  @override
  void initState() {
    super.initState();
    
    // Create providers
    _authProvider = AuthProvider();
    _feederProvider = FeederProvider();
    
    // Connect auth changes to feeder provider
    _authProvider.setAuthStateCallback((userId) {
      _feederProvider.onUserChanged(userId);
    });
  }
  
  @override
  void dispose() {
    _authProvider.dispose();
    _feederProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _feederProvider),
      ],
      child: MaterialApp(
        title: 'Smart Cat Feeder',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
