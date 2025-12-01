import 'dart:io';
import 'package:flutter/foundation.dart';

/// Application configuration
class AppConfig {
  /// Google Sign-In Client ID (for mobile platforms)
  /// Get this from Firebase Console > Authentication > Sign-in method > Google
  /// IMPORTANT: This is required for Google Sign-In to work in production
  static const String googleClientId = String.fromEnvironment(
    'GOOGLE_CLIENT_ID',
    defaultValue: '', // Empty in development, must be set in production
  );

  /// Google Sign-In Server Client ID (for web/backend token verification)
  /// This is typically the Web Client ID from Google Cloud Console
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '', // Empty in development, must be set in production
  );

  /// Validate that Google Client ID is configured (required in production)
  static bool get isGoogleClientIdConfigured {
    return googleClientId.isNotEmpty;
  }

  /// RevenueCat API key
  /// Get your key from: https://app.revenuecat.com/
  ///
  /// IMPORTANT: Configure platform-specific API keys
  /// - iOS: Set REVENUECAT_API_KEY_IOS in build arguments
  /// - Android: Set REVENUECAT_API_KEY_ANDROID in build arguments
  /// - Get keys from RevenueCat dashboard after setting up App Store/Play Store integration
  ///
  /// Build with: flutter build --dart-define=REVENUECAT_API_KEY_IOS=your_key_here
  static String get revenueCatApiKey {
    if (Platform.isIOS) {
      return const String.fromEnvironment(
        'REVENUECAT_API_KEY_IOS',
        defaultValue: '', // Must be set for production iOS builds
      );
    } else if (Platform.isAndroid) {
      return const String.fromEnvironment(
        'REVENUECAT_API_KEY_ANDROID',
        defaultValue: '', // Must be set for production Android builds
      );
    }
    return ''; // Unsupported platform
  }

  /// Validate that RevenueCat is configured (required for subscription features)
  static bool get isRevenueCatConfigured {
    return revenueCatApiKey.isNotEmpty;
  }

  /// Backend service URLs
  ///
  /// IMPORTANT: For production deployment:
  /// 1. Deploy services to Railway: `railway up`
  /// 2. Link project: `railway link`
  /// 3. Get service URLs from Railway dashboard:
  ///    - Go to project settings
  ///    - Select each service
  ///    - Copy the domain (e.g., auth-service-production-abc123.up.railway.app)
  /// 4. Replace the placeholder URLs below with your actual Railway URLs
  ///
  /// For local development, the app automatically uses localhost URLs when
  /// running in debug mode (see getters below).

  // Production URLs - Railway deployment (updated 2025-11-30)
  static const String _prodAuthServiceUrl = 'https://vlvtauth.up.railway.app';
  static const String _prodProfileServiceUrl = 'https://vlvtprofiles.up.railway.app';
  static const String _prodChatServiceUrl = 'https://vlvtchat.up.railway.app';

  /// Auth Service URL with local development fallback
  ///
  /// In debug mode: Uses localhost (or 10.0.2.2 for Android emulator)
  /// In release mode: Uses Railway production URL
  /// Override with: flutter run --dart-define=USE_PROD_URLS=true
  static String get authServiceUrl {
    const forceProd = String.fromEnvironment('USE_PROD_URLS', defaultValue: 'false');

    if (!kReleaseMode && forceProd != 'true') {
      // Local development mode
      return Platform.isAndroid
          ? 'http://10.0.2.2:3001' // Android emulator localhost
          : 'http://localhost:3001'; // iOS simulator or web
    }
    return _prodAuthServiceUrl;
  }

  /// Profile Service URL with local development fallback
  ///
  /// In debug mode: Uses localhost (or 10.0.2.2 for Android emulator)
  /// In release mode: Uses Railway production URL
  /// Override with: flutter run --dart-define=USE_PROD_URLS=true
  static String get profileServiceUrl {
    const forceProd = String.fromEnvironment('USE_PROD_URLS', defaultValue: 'false');

    if (!kReleaseMode && forceProd != 'true') {
      // Local development mode
      return Platform.isAndroid
          ? 'http://10.0.2.2:3002' // Android emulator localhost
          : 'http://localhost:3002'; // iOS simulator or web
    }
    return _prodProfileServiceUrl;
  }

  /// Chat Service URL with local development fallback
  ///
  /// In debug mode: Uses localhost (or 10.0.2.2 for Android emulator)
  /// In release mode: Uses Railway production URL
  /// Override with: flutter run --dart-define=USE_PROD_URLS=true
  static String get chatServiceUrl {
    const forceProd = String.fromEnvironment('USE_PROD_URLS', defaultValue: 'false');

    if (!kReleaseMode && forceProd != 'true') {
      // Local development mode
      return Platform.isAndroid
          ? 'http://10.0.2.2:3003' // Android emulator localhost
          : 'http://localhost:3003'; // iOS simulator or web
    }
    return _prodChatServiceUrl;
  }
}
