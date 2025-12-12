import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:http_parser/http_parser.dart';
import '../config/app_config.dart';
import '../models/profile.dart';
import 'auth_service.dart';
import 'analytics_service.dart';

class ProfileApiService extends ChangeNotifier {
  final AuthService _authService;

  ProfileApiService(this._authService);

  String get baseUrl => AppConfig.profileServiceUrl;

  Map<String, String> _getAuthHeaders() {
    final token = _authService.token;
    if (token == null) {
      debugPrint('Warning: No auth token available for API request');
      return {
        'Content-Type': 'application/json',
      };
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Make a GET request with automatic 401 retry after token refresh
  Future<http.Response> _authenticatedGet(Uri uri) async {
    var response = await http.get(uri, headers: _getAuthHeaders());

    if (response.statusCode == 401) {
      debugPrint('Got 401, attempting token refresh...');
      final refreshed = await _authService.refreshToken();
      if (refreshed) {
        debugPrint('Token refreshed, retrying request...');
        response = await http.get(uri, headers: _getAuthHeaders());
      }
    }

    return response;
  }

  /// Make a POST request with automatic 401 retry after token refresh
  Future<http.Response> _authenticatedPost(Uri uri, {Object? body}) async {
    var response = await http.post(uri, headers: _getAuthHeaders(), body: body);

    if (response.statusCode == 401) {
      debugPrint('Got 401, attempting token refresh...');
      final refreshed = await _authService.refreshToken();
      if (refreshed) {
        debugPrint('Token refreshed, retrying request...');
        response = await http.post(uri, headers: _getAuthHeaders(), body: body);
      }
    }

    return response;
  }

  /// Make a PUT request with automatic 401 retry after token refresh
  Future<http.Response> _authenticatedPut(Uri uri, {Object? body}) async {
    var response = await http.put(uri, headers: _getAuthHeaders(), body: body);

    if (response.statusCode == 401) {
      debugPrint('Got 401, attempting token refresh...');
      final refreshed = await _authService.refreshToken();
      if (refreshed) {
        debugPrint('Token refreshed, retrying request...');
        response = await http.put(uri, headers: _getAuthHeaders(), body: body);
      }
    }

    return response;
  }

  /// Make a DELETE request with automatic 401 retry after token refresh
  Future<http.Response> _authenticatedDelete(Uri uri) async {
    var response = await http.delete(uri, headers: _getAuthHeaders());

    if (response.statusCode == 401) {
      debugPrint('Got 401, attempting token refresh...');
      final refreshed = await _authService.refreshToken();
      if (refreshed) {
        debugPrint('Token refreshed, retrying request...');
        response = await http.delete(uri, headers: _getAuthHeaders());
      }
    }

    return response;
  }

  Future<Profile> getProfile(String userId) async {
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final response = await _authenticatedGet(
        Uri.parse('$baseUrl/profile/$encodedUserId'),
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

  Future<List<Profile>> getDiscoveryProfiles({
    int? minAge,
    int? maxAge,
    double? maxDistance,
    List<String>? interests,
    List<String>? excludeUserIds,
    bool? verifiedOnly,
  }) async {
    try {
      // Build query parameters
      final Map<String, String> queryParams = {};

      if (minAge != null) queryParams['minAge'] = minAge.toString();
      if (maxAge != null) queryParams['maxAge'] = maxAge.toString();
      if (maxDistance != null) queryParams['maxDistance'] = maxDistance.toString();
      if (interests != null && interests.isNotEmpty) {
        queryParams['interests'] = interests.join(',');
      }
      if (excludeUserIds != null && excludeUserIds.isNotEmpty) {
        queryParams['exclude'] = excludeUserIds.join(',');
      }
      if (verifiedOnly == true) {
        queryParams['verifiedOnly'] = 'true';
      }

      final uri = Uri.parse('$baseUrl/profiles/discover').replace(
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      debugPrint('Discovery API: GET $uri');
      debugPrint('Discovery API: Token present: ${_authService.token != null}');

      final response = await _authenticatedGet(uri);

      debugPrint('Discovery API: Response status: ${response.statusCode}');
      if (response.statusCode != 200) {
        debugPrint('Discovery API: Response body: ${response.body}');
      }

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

  Future<Profile> createProfile(Profile profile) async {
    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/profile'),
        body: json.encode(profile.toJson()),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['profile'] != null) {
          final createdProfile = Profile.fromJson(data['profile']);

          // Track profile creation
          await AnalyticsService.logProfileCreated();

          // Set user properties (using age instead of dateOfBirth)
          if (createdProfile.age != null) {
            final ageGroup = AnalyticsService.calculateAgeGroupFromAge(createdProfile.age!);
            await AnalyticsService.setUserProperties(
              ageGroup: ageGroup,
              signupDate: DateTime.now(),
            );
          }

          notifyListeners();
          return createdProfile;
        } else {
          throw Exception('Invalid response format');
        }
      } else if (response.statusCode == 400) {
        final data = json.decode(response.body);
        // Backend returns 'errors' array for validation failures
        if (data['errors'] != null && data['errors'] is List && (data['errors'] as List).isNotEmpty) {
          final errors = data['errors'] as List;
          final messages = errors.map((e) => e['message'] ?? 'Unknown error').join(', ');
          throw Exception(messages);
        }
        throw Exception(data['error'] ?? 'Invalid profile data');
      } else {
        throw Exception('Failed to create profile: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error creating profile: $e');
      rethrow;
    }
  }

  Future<Profile> updateProfile(Profile profile) async {
    try {
      final encodedUserId = Uri.encodeComponent(profile.userId);
      final response = await _authenticatedPut(
        Uri.parse('$baseUrl/profile/$encodedUserId'),
        body: json.encode(profile.toJson()),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['profile'] != null) {
          // Track profile update
          await AnalyticsService.logProfileUpdated();

          notifyListeners();
          return Profile.fromJson(data['profile']);
        } else {
          throw Exception('Invalid response format');
        }
      } else if (response.statusCode == 404) {
        throw Exception('Profile not found');
      } else {
        final data = json.decode(response.body);
        throw Exception(data['error'] ?? 'Failed to update profile: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error updating profile: $e');
      rethrow;
    }
  }

  /// Batch fetch multiple profiles at once
  /// Returns a map of userId -> Profile
  Future<Map<String, Profile>> batchGetProfiles(List<String> userIds) async {
    if (userIds.isEmpty) {
      return {};
    }

    try {
      // For now, fetch profiles in parallel
      // In a real app, you'd want a dedicated batch endpoint on the backend
      final futures = userIds.map((userId) => getProfile(userId));
      final profiles = await Future.wait(
        futures,
        eagerError: false, // Continue even if some fail
      );

      final profileMap = <String, Profile>{};
      for (var i = 0; i < userIds.length; i++) {
        profileMap[userIds[i]] = profiles[i];
      }

      return profileMap;
    } catch (e) {
      debugPrint('Error batch getting profiles: $e');
      rethrow;
    }
  }

  // ===== SEARCH METHODS =====

  /// Search for count of users matching criteria (for free users)
  Future<int> searchUserCount(Map<String, dynamic> criteria) async {
    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/profiles/search/count'),
        body: json.encode(criteria),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['count'] as int? ?? 0;
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to search users: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error searching user count: $e');
      rethrow;
    }
  }

  // ===== LOCATION METHODS =====

  /// Update user's location
  Future<bool> updateLocation(double latitude, double longitude) async {
    try {
      final userId = _authService.userId;
      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final encodedUserId = Uri.encodeComponent(userId);
      final response = await _authenticatedPut(
        Uri.parse('$baseUrl/profile/$encodedUserId/location'),
        body: json.encode({
          'latitude': latitude,
          'longitude': longitude,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          debugPrint('Location updated successfully');
          notifyListeners();
          return true;
        } else {
          debugPrint('Location update failed: ${data['error']}');
          return false;
        }
      } else {
        debugPrint('Location update failed with status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('Error updating location: $e');
      return false;
    }
  }

  // ===== PHOTO UPLOAD METHODS =====

  /// Upload a photo to the user's profile
  Future<Map<String, dynamic>> uploadPhoto(String imagePath) async {
    try {
      final uri = Uri.parse('$baseUrl/profile/photos/upload');
      final request = http.MultipartRequest('POST', uri);

      // Add authorization header
      final token = _authService.token;
      request.headers['Authorization'] = 'Bearer $token';

      // Add file
      final fileName = imagePath.split('/').last;
      final mimeType = _getMimeType(fileName);

      request.files.add(
        await http.MultipartFile.fromPath(
          'photo',
          imagePath,
          contentType: mimeType,
        ),
      );

      // Send request
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          notifyListeners();
          return data;
        } else {
          throw Exception(data['error'] ?? 'Upload failed');
        }
      } else {
        final data = json.decode(response.body);
        throw Exception(data['error'] ?? 'Failed to upload photo: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error uploading photo: $e');
      rethrow;
    }
  }

  /// Delete a photo from the user's profile
  Future<void> deletePhoto(String photoId) async {
    try {
      final encodedPhotoId = Uri.encodeComponent(photoId);
      final response = await _authenticatedDelete(
        Uri.parse('$baseUrl/profile/photos/$encodedPhotoId'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          notifyListeners();
        } else {
          throw Exception(data['error'] ?? 'Delete failed');
        }
      } else {
        final data = json.decode(response.body);
        throw Exception(data['error'] ?? 'Failed to delete photo: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error deleting photo: $e');
      rethrow;
    }
  }

  /// Reorder photos in the user's profile
  Future<void> reorderPhotos(List<String> photoUrls) async {
    try {
      final response = await _authenticatedPut(
        Uri.parse('$baseUrl/profile/photos/reorder'),
        body: json.encode({'photos': photoUrls}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          notifyListeners();
        } else {
          throw Exception(data['error'] ?? 'Reorder failed');
        }
      } else {
        final data = json.decode(response.body);
        throw Exception(data['error'] ?? 'Failed to reorder photos: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error reordering photos: $e');
      rethrow;
    }
  }

  /// Get MIME type from file extension
  MediaType _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return MediaType('image', 'jpeg');
      case 'png':
        return MediaType('image', 'png');
      case 'heic':
        return MediaType('image', 'heic');
      case 'heif':
        return MediaType('image', 'heif');
      case 'webp':
        return MediaType('image', 'webp');
      default:
        return MediaType('image', 'jpeg');
    }
  }

  // ===== SWIPE METHODS =====

  /// Record a swipe (like/pass) and check for mutual match
  /// Returns a map with:
  /// - success: bool
  /// - action: 'like' or 'pass'
  /// - isMatch: bool (true if mutual like detected)
  /// - message: String
  Future<Map<String, dynamic>> swipe({
    required String targetUserId,
    required String action,
  }) async {
    try {
      final response = await _authenticatedPost(
        Uri.parse('$baseUrl/swipes'),
        body: json.encode({
          'targetUserId': targetUserId,
          'action': action,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return {
            'success': true,
            'action': data['action'],
            'isMatch': data['isMatch'] ?? false,
            'message': data['message'],
          };
        } else {
          throw Exception(data['error'] ?? 'Swipe failed');
        }
      } else {
        final data = json.decode(response.body);
        throw Exception(data['error'] ?? 'Failed to record swipe: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error recording swipe: $e');
      rethrow;
    }
  }

  /// Get users who have liked the current user
  Future<List<Map<String, dynamic>>> getReceivedLikes() async {
    try {
      final response = await _authenticatedGet(
        Uri.parse('$baseUrl/swipes/received'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['likes'] != null) {
          return List<Map<String, dynamic>>.from(data['likes']);
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to get received likes: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting received likes: $e');
      rethrow;
    }
  }

  /// Get users the current user has liked (sent likes)
  Future<List<Map<String, dynamic>>> getSentLikes() async {
    try {
      final response = await _authenticatedGet(
        Uri.parse('$baseUrl/swipes/sent'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['likes'] != null) {
          return List<Map<String, dynamic>>.from(data['likes']);
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to get sent likes: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting sent likes: $e');
      rethrow;
    }
  }
}
