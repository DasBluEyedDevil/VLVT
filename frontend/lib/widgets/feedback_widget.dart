import 'package:flutter/material.dart';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'vlvt_input.dart';

/// Beta Feedback Widget
///
/// A floating action button that opens a feedback form.
/// Collects user feedback and device information for beta testing.
///
/// Usage:
/// ```dart
/// FeedbackWidget(
///   onSubmit: (feedback) async {
///     // Send feedback to backend or email
///   },
/// )
/// ```
class FeedbackWidget extends StatelessWidget {
  final Future<void> Function(FeedbackData) onSubmit;

  const FeedbackWidget({
    super.key,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => FeedbackForm(onSubmit: onSubmit),
        );
      },
      backgroundColor: Colors.deepPurple,
      child: const Icon(Icons.feedback),
    );
  }
}

/// Feedback Form Modal
class FeedbackForm extends StatefulWidget {
  final Future<void> Function(FeedbackData) onSubmit;

  const FeedbackForm({
    super.key,
    required this.onSubmit,
  });

  @override
  State<FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends State<FeedbackForm> {
  final _formKey = GlobalKey<FormState>();
  final _feedbackController = TextEditingController();

  FeedbackType _selectedType = FeedbackType.general;
  int _rating = 3;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final deviceInfo = await _getDeviceInfo();
      final appInfo = await _getAppInfo();

      final feedback = FeedbackData(
        type: _selectedType,
        rating: _rating,
        message: _feedbackController.text,
        deviceInfo: deviceInfo,
        appInfo: appInfo,
        timestamp: DateTime.now(),
      );

      await widget.onSubmit(feedback);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thank you for your feedback!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit feedback: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return {
          'platform': 'Android',
          'model': androidInfo.model,
          'manufacturer': androidInfo.manufacturer,
          'os_version': 'Android ${androidInfo.version.release}',
          'sdk_int': androidInfo.version.sdkInt,
        };
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return {
          'platform': 'iOS',
          'model': iosInfo.model,
          'os_version': '${iosInfo.systemName} ${iosInfo.systemVersion}',
          'device': iosInfo.utsname.machine,
        };
      }
    } catch (e) {
      // Fallback if device info fails
      return {
        'platform': Platform.operatingSystem,
        'error': 'Could not retrieve device details',
      };
    }

    return {
      'platform': Platform.operatingSystem,
    };
  }

  Future<Map<String, dynamic>> _getAppInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return {
        'app_name': packageInfo.appName,
        'package_name': packageInfo.packageName,
        'version': packageInfo.version,
        'build_number': packageInfo.buildNumber,
      };
    } catch (e) {
      return {
        'error': 'Could not retrieve app info',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Beta Feedback',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your feedback helps us improve VLVT',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 24),

                // Feedback Type
                const Text(
                  'What type of feedback?',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: FeedbackType.values.map((type) {
                    final isSelected = _selectedType == type;
                    return ChoiceChip(
                      label: Text(_getFeedbackTypeLabel(type)),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedType = type;
                          });
                        }
                      },
                      selectedColor: Colors.deepPurple,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Rating
                const Text(
                  'Overall Rating',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    final starValue = index + 1;
                    return IconButton(
                      icon: Icon(
                        starValue <= _rating
                            ? Icons.star
                            : Icons.star_border,
                        color: Colors.amber,
                        size: 36,
                      ),
                      onPressed: () {
                        setState(() {
                          _rating = starValue;
                        });
                      },
                    );
                  }),
                ),
                const SizedBox(height: 24),

                // Feedback Message
                const Text(
                  'Your Feedback',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                VlvtInput(
                  controller: _feedbackController,
                  maxLines: 5,
                  maxLength: 1000,
                  hintText: 'Tell us what you think...',
                  blur: false,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your feedback';
                    }
                    if (value.trim().length < 10) {
                      return 'Please provide more detail (at least 10 characters)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '${_feedbackController.text.length}/1000 characters',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.right,
                ),
                const SizedBox(height: 24),

                // Submit Button
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitFeedback,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Submit Feedback',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
                const SizedBox(height: 12),

                // Privacy Notice
                const Text(
                  'Device and app information will be included to help us debug issues.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getFeedbackTypeLabel(FeedbackType type) {
    switch (type) {
      case FeedbackType.bug:
        return 'Bug';
      case FeedbackType.feature:
        return 'Feature Request';
      case FeedbackType.ux:
        return 'UX Feedback';
      case FeedbackType.performance:
        return 'Performance';
      case FeedbackType.general:
        return 'General';
    }
  }
}

/// Feedback Type Enum
enum FeedbackType {
  bug,
  feature,
  ux,
  performance,
  general,
}

/// Feedback Data Model
class FeedbackData {
  final FeedbackType type;
  final int rating;
  final String message;
  final Map<String, dynamic> deviceInfo;
  final Map<String, dynamic> appInfo;
  final DateTime timestamp;

  FeedbackData({
    required this.type,
    required this.rating,
    required this.message,
    required this.deviceInfo,
    required this.appInfo,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type.toString().split('.').last,
      'rating': rating,
      'message': message,
      'device_info': deviceInfo,
      'app_info': appInfo,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  String toEmailBody() {
    final buffer = StringBuffer();

    buffer.writeln('Feedback Type: ${type.toString().split('.').last}');
    buffer.writeln('Rating: $rating/5 stars');
    buffer.writeln('Timestamp: ${timestamp.toIso8601String()}');
    buffer.writeln();
    buffer.writeln('--- User Feedback ---');
    buffer.writeln(message);
    buffer.writeln();
    buffer.writeln('--- Device Information ---');
    deviceInfo.forEach((key, value) {
      buffer.writeln('$key: $value');
    });
    buffer.writeln();
    buffer.writeln('--- App Information ---');
    appInfo.forEach((key, value) {
      buffer.writeln('$key: $value');
    });

    return buffer.toString();
  }
}

/// Example usage in Profile Screen:
///
/// ```dart
/// Scaffold(
///   body: ProfileContent(),
///   floatingActionButton: FeedbackWidget(
///     onSubmit: (feedback) async {
///       // Option 1: Send to email
///       final emailService = EmailService();
///       await emailService.sendFeedback(feedback);
///
///       // Option 2: Send to backend API
///       final response = await http.post(
///         Uri.parse('https://api.nobsdating.app/feedback'),
///         headers: {'Content-Type': 'application/json'},
///         body: jsonEncode(feedback.toJson()),
///       );
///
///       // Option 3: Log to Firebase Analytics
///       FirebaseAnalytics.instance.logEvent(
///         name: 'beta_feedback',
///         parameters: feedback.toJson(),
///       );
///     },
///   ),
/// )
/// ```
