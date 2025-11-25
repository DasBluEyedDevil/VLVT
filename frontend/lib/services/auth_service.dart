import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import 'analytics_service.dart';

class AuthService extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  final _googleSignIn = GoogleSignIn.instance;
  bool _isGoogleSignInInitialized = false;

  String? _token;
  String? _userId;
  bool _isAuthenticated = false;

  bool get isAuthenticated => _isAuthenticated;
  String? get userId => _userId;
  String? get token => _token;

  // Base URL for backend - uses AppConfig
  // For iOS simulator: http://localhost:3001
  // For Android emulator: http://10.0.2.2:3001
  // For real device: http://YOUR_COMPUTER_IP:3001
  String get baseUrl => AppConfig.authServiceUrl;

  AuthService() {
    _loadToken();
    _initializeGoogleSignIn();
  }

  Future<void> _initializeGoogleSignIn() async {
    if (!_isGoogleSignInInitialized) {
      // Note: scopes parameter no longer exists in v7.x
      // Scopes are now configured in platform-specific files
      await _googleSignIn.initialize();
      _isGoogleSignInInitialized = true;
    }
  }
  
  Future<void> _loadToken() async {
    _token = await _storage.read(key: 'auth_token');
    _userId = await _storage.read(key: 'user_id');
    if (_token != null && _userId != null) {
      _isAuthenticated = true;
      notifyListeners();
    }
  }
  
  Future<bool> signInWithApple() async {
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      // Send to backend
      final response = await http.post(
        Uri.parse('$baseUrl/auth/apple'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'identityToken': credential.identityToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['token'];
        _userId = data['userId'];

        await _storage.write(key: 'auth_token', value: _token);
        await _storage.write(key: 'user_id', value: _userId);

        _isAuthenticated = true;

        // Track successful login
        await AnalyticsService.logLogin('apple');
        await AnalyticsService.setUserId(_userId!);

        notifyListeners();
        return true;
      }

      // Track failed login
      await AnalyticsService.logLoginFailed('apple', 'backend_error_${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('Error signing in with Apple: $e');

      // Track failed login
      await AnalyticsService.logLoginFailed('apple', e.toString());
      return false;
    }
  }
  
  Future<bool> signInWithGoogle() async {
    try {
      // Validate Google Client ID is configured in production
      if (!kDebugMode && !AppConfig.isGoogleClientIdConfigured) {
        debugPrint('ERROR: Google Client ID is not configured for production!');
        debugPrint('Please set GOOGLE_CLIENT_ID environment variable.');
        await AnalyticsService.logLoginFailed('google', 'missing_client_id');
        return false;
      }

      final account = await _googleSignIn.authenticate(
        scopeHint: const <String>['email', 'profile'],
      );

      final auth = account.authentication;

      // Send to backend
      final response = await http.post(
        Uri.parse('$baseUrl/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'idToken': auth.idToken,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['token'];
        _userId = data['userId'];

        await _storage.write(key: 'auth_token', value: _token);
        await _storage.write(key: 'user_id', value: _userId);

        _isAuthenticated = true;

        // Track successful login
        await AnalyticsService.logLogin('google');
        await AnalyticsService.setUserId(_userId!);

        notifyListeners();
        return true;
      }

      // Track failed login
      await AnalyticsService.logLoginFailed('google', 'backend_error_${response.statusCode}');
      return false;
    } catch (e) {
      debugPrint('Error signing in with Google: $e');

      // Track failed login
      await AnalyticsService.logLoginFailed('google', e.toString());
      return false;
    }
  }
  
  Future<void> signOut() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_id');
    await _googleSignIn.signOut();

    _token = null;
    _userId = null;
    _isAuthenticated = false;
    notifyListeners();
  }

  /// Set auth data directly (used for test login)
  /// This bypasses OAuth and sets authentication state manually
  Future<void> setAuthData({required String token, required String userId}) async {
    _token = token;
    _userId = userId;

    await _storage.write(key: 'auth_token', value: token);
    await _storage.write(key: 'user_id', value: userId);

    _isAuthenticated = true;
    notifyListeners();
  }

  /// Backwards-compatible helper to get the current JWT token.
  /// Falls back to secure storage if the in-memory token is null.
  Future<String?> getToken() async {
    if (_token != null) return _token;
    _token = await _storage.read(key: 'auth_token');
    return _token;
  }

  /// Backwards-compatible helper used by services that only need to know
  /// whether a user is currently logged in.
  /// Returns a minimal user map containing the userId, or null if not logged in.
  Future<Map<String, dynamic>?> getCurrentUser() async {
    var currentUserId = _userId;
    currentUserId ??= await _storage.read(key: 'user_id');
    if (currentUserId == null) return null;
    return {'userId': currentUserId};
  }
}
