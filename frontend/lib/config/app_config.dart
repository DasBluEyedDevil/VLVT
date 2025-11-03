/// Application configuration
class AppConfig {
  /// RevenueCat API key
  /// Get your key from: https://app.revenuecat.com/
  /// Note: Use different keys for iOS and Android
  static const String revenueCatApiKey = String.fromEnvironment(
    'REVENUECAT_API_KEY',
    defaultValue: 'YOUR_REVENUECAT_API_KEY', // Replace with actual key
  );
  
  /// Backend service URLs
  static const String authServiceUrl = String.fromEnvironment(
    'AUTH_SERVICE_URL',
    defaultValue: 'http://localhost:3001',
  );
  
  static const String profileServiceUrl = String.fromEnvironment(
    'PROFILE_SERVICE_URL',
    defaultValue: 'http://localhost:3002',
  );
  
  static const String chatServiceUrl = String.fromEnvironment(
    'CHAT_SERVICE_URL',
    defaultValue: 'http://localhost:3003',
  );
}
