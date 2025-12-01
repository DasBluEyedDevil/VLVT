import 'package:flutter/material.dart';
import '../theme/vlvt_colors.dart';
import 'vlvt_input.dart';
import 'vlvt_button.dart';

class ReportDialog extends StatefulWidget {
  final String userName;
  final Function(String reason, String? details) onSubmit;

  const ReportDialog({
    super.key,
    required this.userName,
    required this.onSubmit,
  });

  @override
  State<ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<ReportDialog> {
  String? _selectedReason;
  final TextEditingController _detailsController = TextEditingController();
  bool _isSubmitting = false;

  final List<Map<String, String>> _reportReasons = [
    {
      'value': 'inappropriate_content',
      'label': 'Inappropriate Content',
      'description': 'Offensive or inappropriate messages or photos',
    },
    {
      'value': 'harassment',
      'label': 'Harassment',
      'description': 'Unwanted contact or threatening behavior',
    },
    {
      'value': 'spam',
      'label': 'Spam',
      'description': 'Commercial or repetitive unwanted messages',
    },
    {
      'value': 'fake_profile',
      'label': 'Fake Profile',
      'description': 'Profile appears to be impersonating someone',
    },
    {
      'value': 'scam',
      'label': 'Scam or Fraud',
      'description': 'Attempting to scam or defraud',
    },
    {
      'value': 'underage',
      'label': 'Underage User',
      'description': 'User appears to be under 18',
    },
    {
      'value': 'other',
      'label': 'Other',
      'description': 'Other reason not listed above',
    },
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reason for reporting')),
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await widget.onSubmit(
        _selectedReason!,
        _detailsController.text.trim().isEmpty ? null : _detailsController.text.trim(),
      );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted. Thank you for helping keep our community safe.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to submit report: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Report ${widget.userName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Why are you reporting this user?',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            RadioGroup<String>(
              groupValue: _selectedReason,
              onChanged: (value) {
                if (!_isSubmitting) {
                  setState(() {
                    _selectedReason = value;
                  });
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _reportReasons.map((reason) {
                  return ListTile(
                    title: Text(reason['label']!),
                    subtitle: Text(
                      reason['description']!,
                      style: const TextStyle(fontSize: 12),
                    ),
                    leading: Radio<String>(
                      value: reason['value']!,
                    ),
                    onTap: _isSubmitting
                        ? null
                        : () {
                            setState(() {
                              _selectedReason = reason['value'];
                            });
                          },
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Additional details (optional):',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            VlvtInput(
              controller: _detailsController,
              hintText: 'Provide any additional information...',
              maxLines: 3,
              maxLength: 500,
              enabled: !_isSubmitting,
              blur: false,
            ),
            const SizedBox(height: 8),
            Text(
              'Reports are anonymous and will be reviewed by our moderation team.',
              style: TextStyle(
                fontSize: 12,
                color: VlvtColors.textMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
      actions: [
        VlvtButton.text(
          label: 'Cancel',
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
        ),
        VlvtButton.danger(
          label: 'Submit Report',
          onPressed: _isSubmitting ? null : _handleSubmit,
          loading: _isSubmitting,
        ),
      ],
    );
  }
}
