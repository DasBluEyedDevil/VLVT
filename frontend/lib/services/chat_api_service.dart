import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../config/app_config.dart';
import '../models/match.dart';
import '../models/message.dart';
import 'analytics_service.dart';
import 'base_api_service.dart';

class ChatApiService extends BaseApiService {
  ChatApiService(super.authService);

  @override
  String get baseUrl => AppConfig.chatServiceUrl;

  Future<List<Match>> getMatches(String userId) async {
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final response = await authenticatedGet(
        Uri.parse('$baseUrl/matches/$encodedUserId'),
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
      final response = await authenticatedGet(
        Uri.parse('$baseUrl/messages/$encodedMatchId'),
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
      final response = await authenticatedPost(
        Uri.parse('$baseUrl/matches'),
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
      final response = await authenticatedPost(
        Uri.parse('$baseUrl/messages'),
        body: json.encode({
          'matchId': matchId,
          'senderId': senderId,
          'text': text,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['message'] != null) {
          // Track message sent
          await AnalyticsService.logMessageSent(matchId);

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

  /// Unmatch with a user - deletes the match
  Future<void> unmatch(String matchId) async {
    try {
      final encodedMatchId = Uri.encodeComponent(matchId);
      final response = await authenticatedDelete(
        Uri.parse('$baseUrl/matches/$encodedMatchId'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] != true) {
          throw Exception('Invalid response format');
        }

        // Track unmatch event
        await AnalyticsService.logUnmatch(matchId);

        notifyListeners();
      } else if (response.statusCode == 404) {
        throw Exception('Match not found');
      } else {
        throw Exception('Failed to unmatch: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error unmatching: $e');
      rethrow;
    }
  }

  /// Get the last message for a specific match
  Future<Message?> getLastMessage(String matchId) async {
    try {
      final messages = await getMessages(matchId);
      if (messages.isEmpty) {
        return null;
      }
      // Messages are typically returned in chronological order, so get the last one
      return messages.last;
    } catch (e) {
      debugPrint('Error getting last message: $e');
      return null; // Return null instead of rethrowing for graceful degradation
    }
  }

  /// Batch get last messages for multiple matches
  /// Returns a map of matchId -> last Message (or null if no messages)
  Future<Map<String, Message?>> batchGetLastMessages(List<String> matchIds) async {
    if (matchIds.isEmpty) {
      return {};
    }

    try {
      // Fetch last messages in parallel
      final futures = matchIds.map((matchId) => getLastMessage(matchId));
      final messages = await Future.wait(
        futures,
        eagerError: false, // Continue even if some fail
      );

      final messageMap = <String, Message?>{};
      for (var i = 0; i < matchIds.length; i++) {
        messageMap[matchIds[i]] = messages[i];
      }

      return messageMap;
    } catch (e) {
      debugPrint('Error batch getting last messages: $e');
      return {}; // Return empty map for graceful degradation
    }
  }

  /// Get unread message counts for all matches of a user
  Future<Map<String, int>> getUnreadCounts(String userId) async {
    try {
      final encodedUserId = Uri.encodeComponent(userId);
      final response = await authenticatedGet(
        Uri.parse('$baseUrl/matches/$encodedUserId/unread-counts'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['unreadCounts'] != null) {
          final Map<String, dynamic> countsMap = data['unreadCounts'];
          return countsMap.map((key, value) => MapEntry(key, value as int));
        } else {
          throw Exception('Invalid response format');
        }
      } else {
        throw Exception('Failed to get unread counts: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error getting unread counts: $e');
      return {}; // Return empty map for graceful degradation
    }
  }

  /// Mark messages as read for a specific match
  Future<void> markMessagesAsRead(String matchId, String userId) async {
    try {
      final encodedMatchId = Uri.encodeComponent(matchId);
      final response = await authenticatedPut(
        Uri.parse('$baseUrl/messages/$encodedMatchId/mark-read'),
        body: json.encode({
          'userId': userId,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Failed to mark messages as read: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error marking messages as read: $e');
      // Don't rethrow - marking as read is not critical
    }
  }
}
