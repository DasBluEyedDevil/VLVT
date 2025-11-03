import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/app_config.dart';
import '../models/match.dart';
import '../models/message.dart';
import 'auth_service.dart';

class ChatApiService extends ChangeNotifier {
  final AuthService _authService;

  ChatApiService(this._authService);

  String get baseUrl => AppConfig.chatServiceUrl;

  Map<String, String> _getAuthHeaders() {
    final token = _authService.token;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Future<List<Match>> getMatches(String userId) async {
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final response = await http.get(
        Uri.parse('$baseUrl/matches/$encodedUserId'),
        headers: _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['matches'] != null) {
          final matchesList = data['matches'] as List;
          return matchesList.map((m) => Match.fromJson(m)).toList();
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to load matches: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting matches: $e');
      rethrow;
    }
  }

  Future<List<Message>> getMessages(String matchId) async {
    try {
      final encodedMatchId = Uri.encodeComponent(matchId);
      final response = await http.get(
        Uri.parse('$baseUrl/messages/$encodedMatchId'),
        headers: _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['messages'] != null) {
          final messagesList = data['messages'] as List;
          return messagesList.map((m) => Message.fromJson(m)).toList();
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to load messages: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting messages: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> createMatch(String userId1, String userId2) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/matches'),
        headers: _getAuthHeaders(),
        body: json.encode({
          'userId1': userId1,
          'userId2': userId2,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['match'] != null) {
          return {
            'match': Match.fromJson(data['match']),
            'alreadyExists': data['alreadyExists'] == true,
          };
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to create match: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error creating match: $e');
      rethrow;
    }
  }

  Future<Message> sendMessage(String matchId, String senderId, String text) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/messages'),
        headers: _getAuthHeaders(),
        body: json.encode({
          'matchId': matchId,
          'senderId': senderId,
          'text': text,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['message'] != null) {
          return Message.fromJson(data['message']);
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to send message: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      rethrow;
    }
  }
}
