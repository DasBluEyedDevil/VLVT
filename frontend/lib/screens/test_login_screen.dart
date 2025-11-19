import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/auth_service.dart';
import '../config/app_config.dart';
import '../config/app_colors.dart';

/// Test Login Screen - DEVELOPMENT ONLY
/// Provides easy access to test user accounts for testing the app
/// This should be hidden or removed in production builds
class TestLoginScreen extends StatefulWidget {
  const TestLoginScreen({super.key});

  @override
  State<TestLoginScreen> createState() => _TestLoginScreenState();
}

class _TestLoginScreenState extends State<TestLoginScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  // Test user personas - matches the seeded database
  final List<TestUser> _testUsers = [
    TestUser(
      id: 'google_test001',
      name: 'Alex Chen',
      age: 28,
      emoji: '👨‍💻',
      bio: 'Software engineer, foodie, adventurer',
      interests: ['Cooking', 'Tech', 'Travel', 'Photography'],
    ),
    TestUser(
      id: 'google_test002',
      name: 'Jordan Rivera',
      age: 25,
      emoji: '🧘',
      bio: 'Yoga instructor, positive vibes',
      interests: ['Yoga', 'Fitness', 'Coffee', 'Nature'],
    ),
    TestUser(
      id: 'google_test003',
      name: 'Sam Patel',
      age: 31,
      emoji: '🎵',
      bio: 'Marketing strategist, music lover',
      interests: ['Music', 'Concerts', 'Vinyl', 'Comedy'],
    ),
    TestUser(
      id: 'google_test004',
      name: 'Taylor Kim',
      age: 27,
      emoji: '🎨',
      bio: 'Graphic designer, art enthusiast',
      interests: ['Art', 'Design', 'Museums'],
    ),
    TestUser(
      id: 'google_test005',
      name: 'Morgan Santos',
      age: 29,
      emoji: '🧗',
      bio: 'Rock climbing addict',
      interests: ['Climbing', 'Outdoors', 'Fitness', 'Travel'],
    ),
    TestUser(
      id: 'google_test006',
      name: 'Casey Nguyen',
      age: 26,
      emoji: '🎲',
      bio: 'Teacher, board game fan',
      interests: ['Board Games', 'Teaching', 'Comedy'],
    ),
    TestUser(
      id: 'google_test007',
      name: 'Riley Anderson',
      age: 30,
      emoji: '📊',
      bio: 'Data scientist, craft beer lover',
      interests: ['Science', 'Beer', 'Books', 'Philosophy'],
    ),
    TestUser(
      id: 'google_test008',
      name: 'Avery Williams',
      age: 24,
      emoji: '📷',
      bio: 'Photographer, dog lover',
      interests: ['Photography', 'Dogs', 'Nature', 'Art'],
    ),
    TestUser(
      id: 'google_test009',
      name: 'Drew Martinez',
      age: 32,
      emoji: '💼',
      bio: 'Entrepreneur, go-getter',
      interests: ['Entrepreneurship', 'Travel', 'Fitness'],
    ),
    TestUser(
      id: 'google_test010',
      name: 'Charlie Lee',
      age: 28,
      emoji: '📚',
      bio: 'Bookworm, aspiring novelist',
      interests: ['Reading', 'Writing', 'Coffee', 'Art'],
    ),
    TestUser(
      id: 'google_test011',
      name: 'Jamie Brown',
      age: 26,
      emoji: '💪',
      bio: 'Personal trainer',
      interests: ['Fitness', 'Health', 'Cooking', 'Running'],
    ),
    TestUser(
      id: 'google_test012',
      name: 'Quinn Davis',
      age: 29,
      emoji: '🏛️',
      bio: 'Architect',
      interests: ['Architecture', 'Design', 'Travel'],
    ),
    TestUser(
      id: 'google_test013',
      name: 'Reese Garcia',
      age: 27,
      emoji: '🐠',
      bio: 'Marine biologist',
      interests: ['Scuba Diving', 'Ocean', 'Science'],
    ),
    TestUser(
      id: 'google_test014',
      name: 'Skylar Wilson',
      age: 25,
      emoji: '🧁',
      bio: 'Pastry chef',
      interests: ['Baking', 'Cooking', 'Food', 'Coffee'],
    ),
    TestUser(
      id: 'google_test015',
      name: 'Blake Moore',
      age: 30,
      emoji: '⚖️',
      bio: 'Lawyer, comedian',
      interests: ['Comedy', 'Improv', 'Debate', 'Theater'],
    ),
    TestUser(
      id: 'google_test016',
      name: 'Phoenix Taylor',
      age: 28,
      emoji: '🎧',
      bio: 'DJ, festival enthusiast',
      interests: ['Music', 'DJing', 'Festivals', 'Dancing'],
    ),
    TestUser(
      id: 'google_test017',
      name: 'Sage Jackson',
      age: 26,
      emoji: '🐾',
      bio: 'Veterinarian, plant parent',
      interests: ['Animals', 'Plants', 'Nature', 'Hiking'],
    ),
    TestUser(
      id: 'google_test018',
      name: 'Dakota White',
      age: 31,
      emoji: '✈️',
      bio: 'Financial advisor, travel hacker',
      interests: ['Travel', 'Finance', 'Wine'],
    ),
    TestUser(
      id: 'google_test019',
      name: 'River Harris',
      age: 24,
      emoji: '🎮',
      bio: 'Video game developer',
      interests: ['Gaming', 'Anime', 'Technology', 'Coding'],
    ),
    TestUser(
      id: 'google_test020',
      name: 'Ocean Clark',
      age: 27,
      emoji: '🌱',
      bio: 'Environmental scientist',
      interests: ['Environment', 'Sustainability', 'Vegan'],
    ),
  ];

  Future<void> _loginAsTestUser(TestUser user) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.authServiceUrl}/auth/test-login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'userId': user.id}),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final authService = context.read<AuthService>();
          // Manually set the auth data
          await authService.setAuthData(
            token: data['token'],
            userId: data['userId'],
          );

          if (mounted) {
            // Success! Navigation will be handled by AuthWrapper
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Logged in as ${user.name}!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          throw Exception(data['error'] ?? 'Login failed');
        }
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to login: $e';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test User Login'),
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? AppColors.primaryDark
            : AppColors.primaryLight,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Warning banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.orange.shade100,
            child: Row(
              children: [
                const Icon(Icons.warning, color: Colors.orange),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'DEVELOPMENT ONLY - These are test accounts for app testing',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Error message
          if (_errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: Colors.red.shade100,
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),

          // Loading indicator
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),

          // User list
          Expanded(
            child: ListView.builder(
              itemCount: _testUsers.length,
              padding: const EdgeInsets.all(8),
              itemBuilder: (context, index) {
                final user = _testUsers[index];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context).brightness == Brightness.dark
                          ? AppColors.primaryDark.withOpacity(0.3)
                          : AppColors.primaryLight.withOpacity(0.3),
                      child: Text(
                        user.emoji,
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
                    title: Text(
                      '${user.name}, ${user.age}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.bio),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          children: user.interests.take(3).map((interest) {
                            return Chip(
                              label: Text(interest),
                              labelStyle: const TextStyle(fontSize: 10),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                    trailing: ElevatedButton(
                      onPressed: _isLoading ? null : () => _loginAsTestUser(user),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).brightness == Brightness.dark
                            ? AppColors.primaryDark
                            : AppColors.primaryLight,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Login'),
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
          ),

          // Instructions
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).brightness == Brightness.dark
                ? AppColors.surface(context)
                : Colors.grey.shade100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💡 Testing Tips:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('• Alex (001) has active conversations'),
                const Text('• Ocean (020) is perfect for testing discovery'),
                const Text('• River (019) is great for testing matches'),
                const Text('• All users start without premium (demo mode)'),
                const SizedBox(height: 8),
                Text(
                  'See backend/seed-data/README.md for details',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Test user data model
class TestUser {
  final String id;
  final String name;
  final int age;
  final String emoji;
  final String bio;
  final List<String> interests;

  TestUser({
    required this.id,
    required this.name,
    required this.age,
    required this.emoji,
    required this.bio,
    required this.interests,
  });
}
