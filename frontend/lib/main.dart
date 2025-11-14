import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'services/auth_service.dart';
import 'services/subscription_service.dart';
import 'services/profile_api_service.dart';
import 'services/chat_api_service.dart';
import 'services/socket_service.dart';
import 'services/location_service.dart';
import 'services/cache_service.dart';
import 'services/safety_service.dart';
import 'services/discovery_preferences_service.dart';
import 'services/analytics_service.dart';
import 'services/notification_service.dart';
import 'screens/auth_screen.dart';
import 'screens/main_screen.dart';
import 'screens/chat_screen.dart';

// Global navigator key for navigation from notification callbacks
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase (will fail gracefully if not configured)
  try {
    await Firebase.initializeApp();

    // Initialize Crashlytics
    if (!kDebugMode) {
      // Only enable crash reporting in release mode
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

      // Catch errors from the platform
      PlatformDispatcher.instance.onError = (error, stack) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
        return true;
      };
    } else {
      // In debug mode, still initialize but don't send crashes
      debugPrint('Firebase Crashlytics initialized in debug mode (not sending crashes)');
    }

    // Initialize Analytics
    // Analytics works in both debug and release mode
    debugPrint('Firebase Analytics initialized');

    // Initialize Notification Service
    final notificationService = NotificationService();
    await notificationService.initialize();

    // Set up notification tap handler
    notificationService.onNotificationTap = (data) {
      _handleNotificationTap(data);
    };

    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
    debugPrint('App will continue without crash reporting and analytics.');
    debugPrint('To enable Firebase, follow instructions in FIREBASE_SETUP.md');
  }

  runApp(const MyApp());
}

/// Handle notification tap - navigate to appropriate screen
void _handleNotificationTap(Map<String, dynamic> data) {
  final type = data['type'];

  if (type == 'message') {
    // Navigate to chat screen
    final matchId = data['matchId'];
    if (matchId != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(matchId: matchId),
        ),
      );
    }
  } else if (type == 'match') {
    // Navigate to matches tab
    // The MainScreen will handle showing the matches tab
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (context) => const MainScreen(initialTab: 1), // 1 = Matches tab
      ),
      (route) => false,
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => SubscriptionService()),
        ChangeNotifierProvider(create: (_) => CacheService()),
        ChangeNotifierProvider(create: (_) => DiscoveryPreferencesService()),
        ChangeNotifierProxyProvider<AuthService, ProfileApiService>(
          create: (context) => ProfileApiService(context.read<AuthService>()),
          update: (context, auth, previous) => ProfileApiService(auth),
        ),
        ChangeNotifierProxyProvider<AuthService, ChatApiService>(
          create: (context) => ChatApiService(context.read<AuthService>()),
          update: (context, auth, previous) => ChatApiService(auth),
        ),
        ChangeNotifierProxyProvider<AuthService, SocketService>(
          create: (context) => SocketService(context.read<AuthService>()),
          update: (context, auth, previous) => previous ?? SocketService(auth),
        ),
        ChangeNotifierProxyProvider<ProfileApiService, LocationService>(
          create: (context) => LocationService(context.read<ProfileApiService>()),
          update: (context, profile, previous) => previous ?? LocationService(profile),
        ),
        ChangeNotifierProxyProvider<AuthService, SafetyService>(
          create: (context) => SafetyService(context.read<AuthService>()),
          update: (context, auth, previous) => SafetyService(auth),
        ),
      ],
      child: MaterialApp(
        title: 'NoBS Dating',
        navigatorKey: navigatorKey,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        navigatorObservers: [
          AnalyticsService.getObserver(),
        ],
        home: const AuthWrapper(),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    
    if (authService.isAuthenticated) {
      return const MainScreen();
    } else {
      return const AuthScreen();
    }
  }
}
