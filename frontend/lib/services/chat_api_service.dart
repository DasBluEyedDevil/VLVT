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
}
