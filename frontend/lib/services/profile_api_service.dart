import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../models/profile.dart';
import 'auth_service.dart';

class ProfileApiService extends ChangeNotifier {
  final AuthService _authService;

  ProfileApiService(this._authService);

  String get baseUrl => AppConfig.profileServiceUrl;

  Map<String, String> _getAuthHeaders() {
    final token = _authService.token;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<Profile> getProfile(String userId) async {
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final response = await http.get(
        Uri.parse('$baseUrl/profile/$encodedUserId'),
        headers: _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['profile'] != null) {
          return Profile.fromJson(data['profile']);
        } else {
          throw Exception('Invalid response format');
        }
      } else if (response.statusCode == 404) {
        throw Exception('Profile not found');
      } else {
        throw Exception('Failed to load profile: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting profile: $e');
      rethrow;
    }
  }

  Future<List<Profile>> getDiscoveryProfiles() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/profiles/discover'),
        headers: _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['profiles'] != null) {
          final profilesList = data['profiles'] as List;
          return profilesList.map((p) => Profile.fromJson(p)).toList();
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to load discovery profiles: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting discovery profiles: $e');
      rethrow;
    }
  }

  Future<Profile> updateProfile(Profile profile) async {
    try {
      final encodedUserId = Uri.encodeComponent(profile.userId);
      final response = await http.put(
        Uri.parse('$baseUrl/profile/$encodedUserId'),
        headers: _getAuthHeaders(),
        body: json.encode(profile.toJson()),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['profile'] != null) {
          notifyListeners();
          return Profile.fromJson(data['profile']);
        } else {
          throw Exception('Invalid response format');
        }
      } else if (response.statusCode == 404) {
        throw Exception('Profile not found');
      } else {
        throw Exception('Failed to update profile: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error updating profile: $e');
      rethrow;
    }
  }
}
