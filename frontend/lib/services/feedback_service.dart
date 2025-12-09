import 'dart:convert';
import 'package:http/http.dart' as http;
import '../widgets/feedback_widget.dart';

/// Service for handling beta feedback submissions
///
/// Provides multiple options for sending feedback:
/// 1. Email via backend endpoint
/// 2. Direct API endpoint
/// 3. Firebase Analytics logging
class FeedbackService {
  final String? backendUrl;
  final String? webhookUrl;

  FeedbackService({
    this.backendUrl,
    this.webhookUrl,
  });

  /// Send feedback to backend API endpoint
  Future<void> sendToBackend(FeedbackData feedback) async {
    if (backendUrl == null) {
      throw Exception('Backend URL not configured');
    }

    final response = await http.post(
      Uri.parse('$backendUrl/feedback'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(feedback.toJson()),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to submit feedback: ${response.statusCode}');
    }
  }

  /// Send feedback to webhook (Slack, Discord, etc.)
  Future<void> sendToWebhook(FeedbackData feedback) async {
    if (webhookUrl == null) {
      throw Exception('Webhook URL not configured');
    }

    // Format for Slack/Discord webhook
    final payload = {
      'text': '📝 New Beta Feedback',
      'blocks': [
        {
          'type': 'header',
          'text': {
            'type': 'plain_text',
            'text': '📝 New Beta Feedback',
          },
        },
        {
          'type': 'section',
          'fields': [
            {
              'type': 'mrkdwn',
              'text': '*Type:*\n${feedback.type.toString().split('.').last}',
            },
            {
              'type': 'mrkdwn',
              'text': '*Rating:*\n${'⭐' * feedback.rating}',
            },
          ],
        },
        {
          'type': 'section',
          'text': {
            'type': 'mrkdwn',
            'text': '*Feedback:*\n${feedback.message}',
          },
        },
        {
          'type': 'section',
          'fields': [
            {
              'type': 'mrkdwn',
              'text': '*Device:*\n${feedback.deviceInfo['model'] ?? 'Unknown'}',
            },
            {
              'type': 'mrkdwn',
              'text': '*OS:*\n${feedback.deviceInfo['os_version'] ?? 'Unknown'}',
            },
          ],
        },
        {
          'type': 'context',
          'elements': [
            {
              'type': 'mrkdwn',
              'text': 'App Version: ${feedback.appInfo['version'] ?? 'Unknown'} | ${feedback.timestamp.toIso8601String()}',
            },
          ],
        },
      ],
    };

    final response = await http.post(
      Uri.parse(webhookUrl!),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to send to webhook: ${response.statusCode}');
    }
  }

  /// Send feedback via email (requires backend endpoint)
  Future<void> sendViaEmail(FeedbackData feedback) async {
    if (backendUrl == null) {
      throw Exception('Backend URL not configured');
    }

    final emailPayload = {
      'to': 'beta@getvlvt.vip',
      'subject': 'Beta Feedback: ${feedback.type.toString().split('.').last}',
      'body': feedback.toEmailBody(),
      'feedback_data': feedback.toJson(),
    };

    final response = await http.post(
      Uri.parse('$backendUrl/send-feedback-email'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(emailPayload),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Failed to send email: ${response.statusCode}');
    }
  }
}

/// Example usage:
///
/// ```dart
/// final feedbackService = FeedbackService(
///   backendUrl: 'https://api.nobsdating.app',
///   webhookUrl: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL',
/// );
///
/// FeedbackWidget(
///   onSubmit: (feedback) async {
///     try {
///       // Try webhook first (fastest)
///       await feedbackService.sendToWebhook(feedback);
///     } catch (e) {
///       // Fallback to backend API
///       try {
///         await feedbackService.sendToBackend(feedback);
///       } catch (e) {
///         // Last resort: just log to analytics
///         await FirebaseAnalytics.instance.logEvent(
///           name: 'beta_feedback',
///           parameters: feedback.toJson(),
///         );
///       }
///     }
///   },
/// )
/// ```
