import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/safety_service.dart';
import '../services/profile_api_service.dart';
import '../models/profile.dart';

class SafetySettingsScreen extends StatefulWidget {
  const SafetySettingsScreen({super.key});

  @override
  State<SafetySettingsScreen> createState() => _SafetySettingsScreenState();
}

class _SafetySettingsScreenState extends State<SafetySettingsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _blockedUsers = [];
  Map<String, Profile> _profiles = {};

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final safetyService = context.read<SafetyService>();
      final profileService = context.read<ProfileApiService>();

      final blockedUsers = await safetyService.getBlockedUsersWithProfiles();

      // Load profiles for blocked users
      final Map<String, Profile> profiles = {};
      for (final blocked in blockedUsers) {
        try {
          final profile = await profileService.getProfile(blocked['blockedUserId']);
          profiles[blocked['blockedUserId']] = profile;
        } catch (e) {
          debugPrint('Error loading profile for ${blocked['blockedUserId']}: $e');
        }
      }

      setState(() {
        _blockedUsers = blockedUsers;
        _profiles = profiles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load blocked users: $e')),
        );
      }
    }
  }

  Future<void> _handleUnblock(String userId, String userName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unblock User'),
        content: Text('Are you sure you want to unblock $userName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Unblock'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final safetyService = context.read<SafetyService>();
        await safetyService.unblockUser(userId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$userName has been unblocked')),
          );
          _loadBlockedUsers();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to unblock user: $e')),
          );
        }
      }
    }
  }

  /// Contact support via email
  Future<void> _contactSupport() async {
    const supportEmail = 'support@nobsdating.com';
    const subject = 'NoBS Dating - Safety Concern';
    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        // Fallback: show dialog with support email
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Contact Support'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Please email us at:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    supportEmail,
                    style: const TextStyle(
                      color: Colors.deepPurple,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'We typically respond within 24 hours.',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening email: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety & Privacy'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Blocked Users',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Blocked users cannot see your profile or send you messages.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                child: CircularProgressIndicator(),
              ),
            )
          else if (_blockedUsers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 80,
                      color: Colors.green,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No blocked users',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'You have not blocked anyone yet.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...(_blockedUsers.map((blocked) {
              final userId = blocked['blockedUserId'] as String;
              final profile = _profiles[userId];
              final name = profile?.name ?? 'Unknown User';

              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.grey,
                  child: Text(
                    name[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(name),
                subtitle: Text(
                  'Blocked on ${_formatDate(blocked['createdAt'])}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: ElevatedButton(
                  onPressed: () => _handleUnblock(userId, name),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Unblock'),
                ),
              );
            })).toList(),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Safety Tips',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),
                _SafetyTip(
                  icon: Icons.shield,
                  title: 'Protect Your Personal Information',
                  description:
                      'Never share personal information like your address, financial details, or social security number.',
                ),
                SizedBox(height: 12),
                _SafetyTip(
                  icon: Icons.group,
                  title: 'Meet in Public Places',
                  description:
                      'Always meet in public places for first dates and tell a friend or family member where you\'re going.',
                ),
                SizedBox(height: 12),
                _SafetyTip(
                  icon: Icons.flag,
                  title: 'Report Suspicious Behavior',
                  description:
                      'If someone makes you uncomfortable or exhibits suspicious behavior, report them immediately.',
                ),
                SizedBox(height: 12),
                _SafetyTip(
                  icon: Icons.block,
                  title: 'Trust Your Instincts',
                  description:
                      'If something doesn\'t feel right, don\'t hesitate to block or report the user.',
                ),
              ],
            ),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Need Help?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'If you\'re experiencing harassment or feel unsafe, please contact our support team.',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _contactSupport,
                  icon: const Icon(Icons.support_agent),
                  label: const Text('Contact Support'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic dateTime) {
    if (dateTime == null) return 'Unknown date';
    try {
      final DateTime date = dateTime is DateTime
          ? dateTime
          : DateTime.parse(dateTime.toString());
      return '${date.month}/${date.day}/${date.year}';
    } catch (e) {
      return 'Unknown date';
    }
  }
}

class _SafetyTip extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const _SafetyTip({
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          color: Colors.deepPurple,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
