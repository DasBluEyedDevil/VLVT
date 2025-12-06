import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../config/app_config.dart';
import 'auth_service.dart';

/// Date proposal data model
class DateProposal {
  final String id;
  final String matchId;
  final String proposerId;
  final String? proposerName;
  final String? placeId;
  final String placeName;
  final String? placeAddress;
  final double? placeLat;
  final double? placeLng;
  final DateTime proposedDate;
  final String proposedTime;
  final String? note;
  final String status;
  final DateTime? respondedAt;
  final DateTime? completedAt;
  final bool proposerConfirmed;
  final bool recipientConfirmed;
  final DateTime createdAt;

  DateProposal({
    required this.id,
    required this.matchId,
    required this.proposerId,
    this.proposerName,
    this.placeId,
    required this.placeName,
    this.placeAddress,
    this.placeLat,
    this.placeLng,
    required this.proposedDate,
    required this.proposedTime,
    this.note,
    required this.status,
    this.respondedAt,
    this.completedAt,
    required this.proposerConfirmed,
    required this.recipientConfirmed,
    required this.createdAt,
  });

  factory DateProposal.fromJson(Map<String, dynamic> json) {
    return DateProposal(
      id: json['id'] as String,
      matchId: json['matchId'] as String,
      proposerId: json['proposerId'] as String,
      proposerName: json['proposerName'] as String?,
      placeId: json['placeId'] as String?,
      placeName: json['placeName'] as String,
      placeAddress: json['placeAddress'] as String?,
      placeLat: json['placeLat'] != null ? double.tryParse(json['placeLat'].toString()) : null,
      placeLng: json['placeLng'] != null ? double.tryParse(json['placeLng'].toString()) : null,
      proposedDate: DateTime.parse(json['proposedDate'] as String),
      proposedTime: json['proposedTime'] as String,
      note: json['note'] as String?,
      status: json['status'] as String,
      respondedAt: json['respondedAt'] != null ? DateTime.parse(json['respondedAt'] as String) : null,
      completedAt: json['completedAt'] != null ? DateTime.parse(json['completedAt'] as String) : null,
      proposerConfirmed: json['proposerConfirmed'] as bool? ?? false,
      recipientConfirmed: json['recipientConfirmed'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isDeclined => status == 'declined';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';

  String get formattedDate {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[proposedDate.month - 1]} ${proposedDate.day}';
  }

  String get formattedTime {
    // Parse time like "19:30:00" and format as "7:30 PM"
    final parts = proposedTime.split(':');
    if (parts.length >= 2) {
      int hour = int.tryParse(parts[0]) ?? 0;
      final minute = parts[1];
      final period = hour >= 12 ? 'PM' : 'AM';
      if (hour > 12) hour -= 12;
      if (hour == 0) hour = 12;
      return '$hour:$minute $period';
    }
    return proposedTime;
  }
}

/// Service for managing date proposals
class DateProposalService extends ChangeNotifier {
  final AuthService _authService;

  final Map<String, List<DateProposal>> _proposalsByMatch = {};
  bool _isLoading = false;
  String? _error;

  DateProposalService(this._authService);

  List<DateProposal> getProposalsForMatch(String matchId) => _proposalsByMatch[matchId] ?? [];
  bool get isLoading => _isLoading;
  String? get error => _error;

  String get baseUrl => AppConfig.chatServiceUrl;

  Map<String, String> _getAuthHeaders() {
    final token = _authService.token;
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  /// Load date proposals for a match
  Future<void> loadProposals(String matchId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/dates/$matchId'),
        headers: _getAuthHeaders(),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final proposals = (data['proposals'] as List)
              .map((p) => DateProposal.fromJson(p as Map<String, dynamic>))
              .toList();
          _proposalsByMatch[matchId] = proposals;
        }
      } else {
        _error = 'Failed to load date proposals';
      }
    } catch (e) {
      debugPrint('Error loading date proposals: $e');
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Create a new date proposal
  Future<Map<String, dynamic>> createProposal({
    required String matchId,
    required String placeName,
    required DateTime proposedDate,
    required String proposedTime,
    String? placeId,
    String? placeAddress,
    double? placeLat,
    double? placeLng,
    String? note,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/dates'),
        headers: _getAuthHeaders(),
        body: json.encode({
          'matchId': matchId,
          'placeName': placeName,
          'proposedDate': proposedDate.toIso8601String().split('T')[0],
          'proposedTime': proposedTime,
          if (placeId != null) 'placeId': placeId,
          if (placeAddress != null) 'placeAddress': placeAddress,
          if (placeLat != null) 'placeLat': placeLat,
          if (placeLng != null) 'placeLng': placeLng,
          if (note != null) 'note': note,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // Reload proposals for this match
        await loadProposals(matchId);
        return {'success': true, 'proposal': data['proposal']};
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to create date proposal',
      };
    } catch (e) {
      debugPrint('Error creating date proposal: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Respond to a date proposal (accept/decline)
  Future<Map<String, dynamic>> respondToProposal({
    required String proposalId,
    required String matchId,
    required String response,
    DateTime? counterDate,
    String? counterTime,
  }) async {
    try {
      final body = <String, dynamic>{'response': response};
      if (counterDate != null && counterTime != null) {
        body['counterDate'] = counterDate.toIso8601String().split('T')[0];
        body['counterTime'] = counterTime;
      }

      final httpResponse = await http.put(
        Uri.parse('$baseUrl/dates/$proposalId/respond'),
        headers: _getAuthHeaders(),
        body: json.encode(body),
      );

      final data = json.decode(httpResponse.body);

      if (httpResponse.statusCode == 200 && data['success'] == true) {
        // Reload proposals for this match
        await loadProposals(matchId);
        return {'success': true, 'message': data['message']};
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to respond to proposal',
      };
    } catch (e) {
      debugPrint('Error responding to date proposal: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Confirm a date happened
  Future<Map<String, dynamic>> confirmDate({
    required String proposalId,
    required String matchId,
  }) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl/dates/$proposalId/confirm'),
        headers: _getAuthHeaders(),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // Reload proposals for this match
        await loadProposals(matchId);
        return {
          'success': true,
          'message': data['message'],
          'completed': data['completed'] ?? false,
          'ticketAwarded': data['ticketAwarded'] ?? false,
        };
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to confirm date',
      };
    } catch (e) {
      debugPrint('Error confirming date: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Cancel a date proposal
  Future<Map<String, dynamic>> cancelProposal({
    required String proposalId,
    required String matchId,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/dates/$proposalId'),
        headers: _getAuthHeaders(),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        // Reload proposals for this match
        await loadProposals(matchId);
        return {'success': true, 'message': data['message']};
      }

      return {
        'success': false,
        'error': data['error'] ?? 'Failed to cancel proposal',
      };
    } catch (e) {
      debugPrint('Error cancelling date proposal: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}
