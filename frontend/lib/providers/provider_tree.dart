import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../services/profile_api_service.dart';
import '../services/chat_api_service.dart';
import '../services/socket_service.dart';
import '../services/location_service.dart';
import '../services/cache_service.dart';
import '../services/safety_service.dart';
import '../services/discovery_preferences_service.dart';
import '../services/tickets_service.dart';
import '../services/date_proposal_service.dart';
import '../services/verification_service.dart';
import '../services/message_queue_service.dart';
import '../services/theme_service.dart';

/// Centralized provider configuration for VLVT
/// Organizes providers into feature-based groups for better scoping
/// and reduced global state bloat
class ProviderTree {
  /// Core providers that are needed throughout the entire app
  /// These are initialized at the root level and never disposed
  static List<SingleChildWidget> core(ThemeService themeService) => [
        ChangeNotifierProvider.value(value: themeService),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => SubscriptionService()),
        ChangeNotifierProvider(create: (_) => CacheService()),
      ];

  /// Discovery feature providers
  /// Used for profile browsing, swiping, and filtering
  static List<SingleChildWidget> discovery() => [
        ChangeNotifierProvider(create: (_) => DiscoveryPreferencesService()),
      ];

  /// Profile feature providers
  /// Used for profile management, photos, verification
  static List<SingleChildWidget> profile() => [
        ChangeNotifierProxyProvider<AuthService, ProfileApiService>(
          create: (context) => ProfileApiService(context.read<AuthService>()),
          update: (context, auth, previous) => ProfileApiService(auth),
        ),
        ChangeNotifierProxyProvider<ProfileApiService, LocationService>(
          create: (context) =>
              LocationService(context.read<ProfileApiService>()),
          update: (context, profile, previous) =>
              previous ?? LocationService(profile),
        ),
        ChangeNotifierProxyProvider<AuthService, VerificationService>(
          create: (context) =>
              VerificationService(context.read<AuthService>()),
          update: (context, auth, previous) => VerificationService(auth),
        ),
      ];

  /// Chat feature providers
  /// Used for messaging, matches, and real-time communication
  static List<SingleChildWidget> chat() => [
        ChangeNotifierProvider(create: (_) => MessageQueueService()..init()),
        ChangeNotifierProxyProvider<AuthService, ChatApiService>(
          create: (context) => ChatApiService(context.read<AuthService>()),
          update: (context, auth, previous) => ChatApiService(auth),
        ),
        ChangeNotifierProxyProvider<AuthService, SocketService>(
          create: (context) => SocketService(context.read<AuthService>()),
          update: (context, auth, previous) => previous ?? SocketService(auth),
        ),
      ];

  /// Safety & Support feature providers
  /// Used for reporting, blocking, and support tickets
  static List<SingleChildWidget> safety() => [
        ChangeNotifierProxyProvider<AuthService, SafetyService>(
          create: (context) => SafetyService(context.read<AuthService>()),
          update: (context, auth, previous) => SafetyService(auth),
        ),
        ChangeNotifierProxyProvider<AuthService, TicketsService>(
          create: (context) => TicketsService(context.read<AuthService>()),
          update: (context, auth, previous) => TicketsService(auth),
        ),
      ];

  /// Dating feature providers
  /// Used for date proposals and scheduling
  static List<SingleChildWidget> dating() => [
        ChangeNotifierProxyProvider<AuthService, DateProposalService>(
          create: (context) =>
              DateProposalService(context.read<AuthService>()),
          update: (context, auth, previous) => DateProposalService(auth),
        ),
      ];

  /// Get all providers for the full app (backward compatible)
  /// This includes all feature providers at root level
  /// Use for full app initialization when feature scoping is not needed
  static List<SingleChildWidget> all(ThemeService themeService) => [
        ...core(themeService),
        ...discovery(),
        ...profile(),
        ...chat(),
        ...safety(),
        ...dating(),
      ];

  /// Authenticated user providers
  /// Providers that depend on AuthService and are only needed when logged in
  static List<SingleChildWidget> authenticatedUser() => [
        ...discovery(),
        ...profile(),
        ...chat(),
        ...safety(),
        ...dating(),
      ];
}

/// Extension to easily wrap a widget with feature-specific providers
extension ProviderTreeExtension on Widget {
  /// Wrap with profile feature providers
  Widget withProfileProviders() {
    return MultiProvider(
      providers: ProviderTree.profile(),
      child: this,
    );
  }

  /// Wrap with chat feature providers
  Widget withChatProviders() {
    return MultiProvider(
      providers: ProviderTree.chat(),
      child: this,
    );
  }

  /// Wrap with safety feature providers
  Widget withSafetyProviders() {
    return MultiProvider(
      providers: ProviderTree.safety(),
      child: this,
    );
  }

  /// Wrap with discovery feature providers
  Widget withDiscoveryProviders() {
    return MultiProvider(
      providers: ProviderTree.discovery(),
      child: this,
    );
  }
}
