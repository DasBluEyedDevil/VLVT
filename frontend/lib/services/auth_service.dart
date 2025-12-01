import 'dart:async';
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
  bool _googleSignInInitialized = false;

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
  
  /// Initialize Google Sign-In (must be called before signInWithGoogle)
  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;

    try {
      await _googleSignIn.initialize(
        clientId: AppConfig.googleClientId,
        serverClientId: AppConfig.googleServerClientId,
      );
      _googleSignInInitialized = true;
    } catch (e) {
      debugPrint('Error initializing Google Sign-In: $e');
      rethrow;
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

      // Initialize Google Sign-In if not already done
      await _ensureGoogleSignInInitialized();

      // Use the new v7 API - authenticate and get account via event stream
      final completer = Completer<GoogleSignInAccount?>();
      StreamSubscription<GoogleSignInAuthenticationEvent>? subscription;

      subscription = _googleSignIn.authenticationEvents.listen(
        (event) {
          subscription?.cancel();
          // Extract account from the authentication event
          final GoogleSignInAccount? account = switch (event) {
            GoogleSignInAuthenticationEventSignIn() => event.user,
            GoogleSignInAuthenticationEventSignOut() => null,
          };
          completer.complete(account);
        },
        onError: (error) {
          subscription?.cancel();
          completer.completeError(error);
        },
      );

      // Check if authentication is supported
      if (_googleSignIn.supportsAuthenticate()) {
        await _googleSignIn.authenticate();
      } else {
        // Fallback for platforms without authentication support
        await _googleSignIn.attemptLightweightAuthentication();
      }

      final account = await completer.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () => null,
      );

      if (account == null) {
        await AnalyticsService.logLoginFailed('google', 'user_cancelled');
        return false;
      }

      // Get the ID token from the authenticated account's authentication property
      final auth = account.authentication;
      final idToken = auth.idToken;
      if (idToken == null) {
        await AnalyticsService.logLoginFailed('google', 'no_id_token');
        return false;
      }

      // Send to backend
      final response = await http.post(
        Uri.parse('$baseUrl/auth/google'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'idToken': idToken,
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

  /// Register with email and password
  Future<Map<String, dynamic>> registerWithEmail(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/email/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        await AnalyticsService.logSignupCompleted('email');
        return {'success': true, 'message': data['message']};
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Registration failed',
        'details': data['details'],
      };
    } catch (e) {
      debugPrint('Error registering with email: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Sign in with email and password
  Future<Map<String, dynamic>> signInWithEmail(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/email/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': email,
          'password': password,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        _token = data['token'];
        _userId = data['userId'];

        await _storage.write(key: 'auth_token', value: _token);
        await _storage.write(key: 'user_id', value: _userId);

        _isAuthenticated = true;

        await AnalyticsService.logLogin('email');
        await AnalyticsService.setUserId(_userId!);

        notifyListeners();
        return {'success': true};
      }

      if (data['code'] == 'EMAIL_NOT_VERIFIED') {
        return {'success': false, 'error': data['error'], 'code': 'EMAIL_NOT_VERIFIED'};
      }

      await AnalyticsService.logLoginFailed('email', 'backend_error_${response.statusCode}');
      return {'success': false, 'error': data['error'] ?? 'Login failed'};
    } catch (e) {
      debugPrint('Error signing in with email: $e');
      await AnalyticsService.logLoginFailed('email', e.toString());
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Request password reset email
  Future<bool> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/email/forgot'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error requesting password reset: $e');
      return false;
    }
  }

  /// Reset password with token
  Future<Map<String, dynamic>> resetPassword(String token, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/email/reset'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'token': token,
          'newPassword': newPassword,
        }),
      );

      final data = json.decode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? data['error'],
        'details': data['details'],
      };
    } catch (e) {
      debugPrint('Error resetting password: $e');
      return {'success': false, 'message': e.toString()};
    }
  }

  /// Resend verification email
  Future<bool> resendVerificationEmail(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/email/resend-verification'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'email': email}),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Error resending verification: $e');
      return false;
    }
  }

  /// Verify email with token (called from deep link)
  Future<bool> verifyEmail(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/auth/email/verify?token=$token'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _token = data['token'];
        _userId = data['userId'];

        await _storage.write(key: 'auth_token', value: _token);
        await _storage.write(key: 'user_id', value: _userId);

        _isAuthenticated = true;
        notifyListeners();
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('Error verifying email: $e');
      return false;
    }
  }

  /// Sign in with Instagram - returns either auth data or needsEmail flag
  Future<Map<String, dynamic>> signInWithInstagram(String accessToken) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/instagram'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'accessToken': accessToken}),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        if (data['needsEmail'] == true) {
          return {
            'success': true,
            'needsEmail': true,
            'tempToken': data['tempToken'],
            'username': data['username'],
          };
        }

        _token = data['token'];
        _userId = data['userId'];

        await _storage.write(key: 'auth_token', value: _token);
        await _storage.write(key: 'user_id', value: _userId);

        _isAuthenticated = true;

        await AnalyticsService.logLogin('instagram');
        await AnalyticsService.setUserId(_userId!);

        notifyListeners();
        return {'success': true, 'authenticated': true};
      }

      return {'success': false, 'error': data['error']};
    } catch (e) {
      debugPrint('Error signing in with Instagram: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Complete Instagram registration with email
  Future<Map<String, dynamic>> completeInstagramRegistration(String tempToken, String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/instagram/complete'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'tempToken': tempToken,
          'email': email,
        }),
      );

      final data = json.decode(response.body);
      return {
        'success': response.statusCode == 200,
        'message': data['message'] ?? data['error'],
        'userId': data['userId'],
      };
    } catch (e) {
      debugPrint('Error completing Instagram registration: $e');
      return {'success': false, 'message': e.toString()};
    }
  }
  
  Future<void> signOut() async {
    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'user_id');
    await _googleSignIn.disconnect();

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
