import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'socket_service.dart';

/// Represents a message queued for sending when connection is restored
class QueuedMessage {
  final String tempId;
  final String matchId;
  final String text;
  final DateTime timestamp;

  QueuedMessage({
    required this.tempId,
    required this.matchId,
    required this.text,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
    'tempId': tempId,
    'matchId': matchId,
    'text': text,
    'timestamp': timestamp.toIso8601String(),
  };

  factory QueuedMessage.fromJson(Map<String, dynamic> json) => QueuedMessage(
    tempId: json['tempId'] as String,
    matchId: json['matchId'] as String,
    text: json['text'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
  );
}

/// Service for queuing messages when offline and sending when connection is restored
/// Prevents message loss on spotty networks (cafes, subways, rural areas)
class MessageQueueService extends ChangeNotifier {
  static const String _queueKey = 'offline_message_queue';
  static const Duration _maxMessageAge = Duration(hours: 24); // Auto-delete messages older than 24h

  List<QueuedMessage> _queue = [];
  bool _isProcessing = false;

  List<QueuedMessage> get queue => List.unmodifiable(_queue);
  int get queueLength => _queue.length;

  /// Initialize service and load persisted queue
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getString(_queueKey);

    if (queueJson != null) {
      try {
        final List<dynamic> decoded = json.decode(queueJson);
        _queue = decoded
            .map((m) => QueuedMessage.fromJson(m as Map<String, dynamic>))
            .where((m) => _isMessageFresh(m)) // Remove expired messages
            .toList();

        debugPrint('MessageQueueService: Loaded ${_queue.length} queued messages');
      } catch (e) {
        debugPrint('MessageQueueService: Error loading queue: $e');
        _queue = [];
      }
    }
  }

  /// Check if message is still fresh (not older than 24 hours)
  bool _isMessageFresh(QueuedMessage message) {
    final age = DateTime.now().difference(message.timestamp);
    return age < _maxMessageAge;
  }

  /// Add message to queue
  Future<void> enqueue(QueuedMessage message) async {
    _queue.add(message);
    await _persist();
    notifyListeners();

    debugPrint('MessageQueueService: Queued message ${message.tempId} for match ${message.matchId}');
  }

  /// Remove message from queue
  Future<void> dequeue(String tempId) async {
    final initialLength = _queue.length;
    _queue.removeWhere((m) => m.tempId == tempId);

    if (_queue.length != initialLength) {
      await _persist();
      notifyListeners();
      debugPrint('MessageQueueService: Removed message $tempId from queue');
    }
  }

  /// Get all queued messages for a specific match
  List<QueuedMessage> getQueueForMatch(String matchId) {
    return _queue.where((m) => m.matchId == matchId).toList();
  }

  /// Persist queue to SharedPreferences
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final queueJson = json.encode(_queue.map((m) => m.toJson()).toList());
      await prefs.setString(_queueKey, queueJson);
    } catch (e) {
      debugPrint('MessageQueueService: Error persisting queue: $e');
    }
  }

  /// Process entire queue - send all queued messages
  Future<void> processQueue(SocketService socketService) async {
    if (_isProcessing) {
      debugPrint('MessageQueueService: Already processing queue, skipping');
      return;
    }

    if (!socketService.isConnected || _queue.isEmpty) {
      debugPrint('MessageQueueService: Cannot process - socket connected: ${socketService.isConnected}, queue empty: ${_queue.isEmpty}');
      return;
    }

    _isProcessing = true;
    debugPrint('MessageQueueService: Processing ${_queue.length} queued messages');

    final messagesToSend = List<QueuedMessage>.from(_queue);
    int successCount = 0;
    int failureCount = 0;

    for (final message in messagesToSend) {
      try {
        debugPrint('MessageQueueService: Sending queued message ${message.tempId}');

        await socketService.sendMessage(
          matchId: message.matchId,
          text: message.text,
          tempId: message.tempId,
        );

        await dequeue(message.tempId);
        successCount++;

        // Small delay between messages to avoid overwhelming the server
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        debugPrint('MessageQueueService: Failed to send queued message: $e');
        failureCount++;

        // If one fails, stop trying (probably connection issue)
        break;
      }
    }

    _isProcessing = false;
    debugPrint('MessageQueueService: Queue processing complete - success: $successCount, failed: $failureCount, remaining: ${_queue.length}');
  }

  /// Clear all queued messages (e.g., user logout)
  Future<void> clearAll() async {
    _queue.clear();
    await _persist();
    notifyListeners();
    debugPrint('MessageQueueService: Cleared all queued messages');
  }

  /// Clear queued messages for a specific match
  Future<void> clearMatch(String matchId) async {
    final initialLength = _queue.length;
    _queue.removeWhere((m) => m.matchId == matchId);

    if (_queue.length != initialLength) {
      await _persist();
      notifyListeners();
      debugPrint('MessageQueueService: Cleared ${initialLength - _queue.length} messages for match $matchId');
    }
  }
}
