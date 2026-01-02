import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'providers/feeder_provider.dart';
import 'providers/shelter_provider.dart';
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
  late final ShelterProvider _shelterProvider;
  
  @override
  void initState() {
    super.initState();
    
    // Create providers
    _authProvider = AuthProvider();
    _feederProvider = FeederProvider();
    _shelterProvider = ShelterProvider();
    
    // Connect auth changes to feeder provider
    _authProvider.setAuthStateCallback((userId) {
      _feederProvider.onUserChanged(userId);
      _shelterProvider.onUserChanged(userId);
    });
    
    // Explicitly trigger initial auth state notification after callback is set
    // This handles the race condition where _checkAuthState() might complete
    // before the callback is registered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_authProvider.userId != null) {
        debugPrint('🚀 Post-frame: Triggering initial auth state for userId: ${_authProvider.userId}');
        _feederProvider.onUserChanged(_authProvider.userId);
        _shelterProvider.onUserChanged(_authProvider.userId);
      }
    });
  }
  
  @override
  void dispose() {
    _authProvider.dispose();
    _feederProvider.dispose();
    _shelterProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _authProvider),
        ChangeNotifierProvider.value(value: _feederProvider),
        ChangeNotifierProvider.value(value: _shelterProvider),
      ],
      child: MaterialApp(
        title: 'Shelter Monitor',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const SplashScreen(),
      ),
    );
  }
}
