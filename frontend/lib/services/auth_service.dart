import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';

class AuthService extends ChangeNotifier {
  final _storage = const FlutterSecureStorage();
  final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );
  
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
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error signing in with Apple: $e');
      return false;
    }
  }
  
  Future<bool> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) return false;
      
      final auth = await account.authentication;
      
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
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error signing in with Google: $e');
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
}
