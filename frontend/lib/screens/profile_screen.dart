import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../services/profile_api_service.dart';
import '../models/profile.dart';
import 'profile_edit_screen.dart';
import 'safety_settings_screen.dart';
import '../widgets/feedback_widget.dart';
import '../widgets/theme_toggle_widget.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../config/app_colors.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _refreshKey = 0;

  void _refreshProfile() {
    setState(() {
      _refreshKey++;
    });
  }

  Future<void> _navigateToEditProfile(Profile? currentProfile) async {
    final result = await Navigator.of(context).push<Profile>(
      MaterialPageRoute(
        builder: (context) => ProfileEditScreen(
          existingProfile: currentProfile,
        ),
      ),
    );

    if (result != null) {
      _refreshProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final subscriptionService = context.watch<SubscriptionService>();
    final profileService = context.watch<ProfileApiService>();
    final userId = authService.userId;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await authService.signOut();
              },
            ),
          ],
        ),
        body: const Center(
          child: Text('User not authenticated'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.signOut();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: FutureBuilder<Profile>(
          key: ValueKey(_refreshKey),
          future: profileService.getProfile(userId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Error loading profile: ${snapshot.error}',
                      style: TextStyle(color: AppColors.error(context)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {});
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final profile = snapshot.data;

            return SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                        child: const Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        profile?.name ?? 'Your Name',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        userId,
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Subscription Status',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  subscriptionService.hasPremiumAccess
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: subscriptionService.hasPremiumAccess
                                      ? AppColors.success(context)
                                      : AppColors.error(context),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  subscriptionService.hasPremiumAccess
                                      ? 'Premium Active'
                                      : 'No Active Subscription',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: subscriptionService.hasPremiumAccess
                                        ? AppColors.success(context)
                                        : AppColors.error(context),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: subscriptionService.hasPremiumAccess
                                  ? OutlinedButton.icon(
                                      onPressed: () {
                                        subscriptionService.presentCustomerCenter(context);
                                      },
                                      icon: const Icon(Icons.settings),
                                      label: const Text('Manage Subscription'),
                                    )
                                  : ElevatedButton.icon(
                                      onPressed: () async {
                                        await subscriptionService.presentPaywallIfNeeded();
                                      },
                                      icon: const Icon(Icons.star),
                                      label: const Text('Upgrade to Premium'),
                                    ),
                            ),
                            if (!subscriptionService.hasPremiumAccess) ...[
                              const SizedBox(height: 8),
                              Center(
                                child: TextButton(
                                  onPressed: () async {
                                    final restored = await subscriptionService.restorePurchases();
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(restored
                                              ? 'Purchases restored successfully!'
                                              : 'No purchases to restore'),
                                        ),
                                      );
                                    }
                                  },
                                  child: const Text('Restore Purchases'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Profile Information',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (profile?.age != null) ...[
                              _buildInfoRow('Age', profile!.age.toString()),
                              const Divider(),
                            ],
                            if (profile?.bio != null) ...[
                              _buildInfoRow('Bio', profile!.bio!),
                              const Divider(),
                            ],
                            if (profile?.interests != null && profile!.interests!.isNotEmpty)
                              _buildInfoRow('Interests', profile.interests!.join(', ')),
                            if (!_hasProfileInfo(profile))
                              Text(
                                'No profile information available',
                                style: TextStyle(color: AppColors.textSecondary(context)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => _navigateToEditProfile(profile),
                      icon: const Icon(Icons.edit),
                      label: const Text('Edit Profile'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SafetySettingsScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.security),
                      label: const Text('Safety & Privacy'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const ThemeToggleWidget(),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FeedbackWidget(
        onSubmit: (feedback) async {
          // Log to Firebase Analytics
          await FirebaseAnalytics.instance.logEvent(
            name: 'beta_feedback',
            parameters: feedback.toJson().cast<String, Object>(),
          );
        },
      ),
    );
  }

  bool _hasProfileInfo(Profile? profile) {
    if (profile == null) return false;
    return profile.age != null || 
           profile.bio != null || 
           (profile.interests != null && profile.interests!.isNotEmpty);
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondary(context),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.start,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}
