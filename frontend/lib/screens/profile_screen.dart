import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/subscription_service.dart';
import '../services/profile_api_service.dart';
import '../models/profile.dart';
import 'profile_edit_screen.dart';
import 'safety_settings_screen.dart';
import 'invite_screen.dart';
import 'id_verification_screen.dart';
import '../widgets/feedback_widget.dart';
import '../widgets/vlvt_loader.dart';
import '../widgets/vlvt_card.dart';
import '../widgets/vlvt_button.dart';
import '../theme/vlvt_colors.dart';
import '../theme/vlvt_text_styles.dart';
import 'package:firebase_analytics/firebase_analytics.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int _refreshKey = 0;
  Map<String, dynamic>? _profileCompletionStatus;

  void _refreshProfile() {
    setState(() {
      _refreshKey++;
      _profileCompletionStatus = null; // Reset completion status on refresh
    });
    _checkProfileCompletion();
  }

  Future<void> _checkProfileCompletion() async {
    try {
      final profileService = context.read<ProfileApiService>();
      final result = await profileService.checkProfileCompletion();
      if (mounted) {
        setState(() {
          _profileCompletionStatus = result;
        });
      }
    } catch (e) {
      // Silently fail - don't show error for completion check
    }
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

    if (userId == null) {
      return Scaffold(
        backgroundColor: VlvtColors.background,
        appBar: AppBar(
          backgroundColor: VlvtColors.background,
          title: Text('Profile', style: VlvtTextStyles.h2),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: VlvtColors.gold),
              onPressed: () async {
                await authService.signOut();
              },
            ),
          ],
        ),
        body: Center(
          child: Text('User not authenticated', style: VlvtTextStyles.bodyMedium),
        ),
      );
    }

    return Scaffold(
      backgroundColor: VlvtColors.background,
      appBar: AppBar(
        backgroundColor: VlvtColors.background,
        title: Text('Profile', style: VlvtTextStyles.h2),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: VlvtColors.gold),
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
            // Check profile completion when profile loads
            if (snapshot.hasData && _profileCompletionStatus == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _checkProfileCompletion();
              });
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: VlvtLoader(),
              );
            }

            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Error loading profile: ${snapshot.error}',
                      style: VlvtTextStyles.bodyMedium.copyWith(color: VlvtColors.crimson),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    VlvtButton.primary(
                      label: 'Retry',
                      onPressed: () {
                        setState(() {});
                      },
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
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: VlvtColors.gold, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: VlvtColors.gold.withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: CircleAvatar(
                          radius: 60,
                          backgroundColor: VlvtColors.primary,
                          child: const Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Center(
                      child: Text(
                        profile?.name ?? 'Your Name',
                        style: VlvtTextStyles.displayMedium,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        userId,
                        style: VlvtTextStyles.bodySmall.copyWith(
                          color: VlvtColors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Profile completion banner
                    if (_profileCompletionStatus != null &&
                        _profileCompletionStatus!['isComplete'] != true)
                      _buildProfileCompletionBanner(),
                    if (_profileCompletionStatus != null &&
                        _profileCompletionStatus!['isComplete'] != true)
                      const SizedBox(height: 16),
                    VlvtCard(
                      goldAccent: subscriptionService.hasPremiumAccess,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Subscription Status',
                            style: VlvtTextStyles.h3.copyWith(color: VlvtColors.gold),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                subscriptionService.hasPremiumAccess
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                color: subscriptionService.hasPremiumAccess
                                    ? VlvtColors.success
                                    : VlvtColors.crimson,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                subscriptionService.hasPremiumAccess
                                    ? 'Premium Active'
                                    : 'No Active Subscription',
                                style: VlvtTextStyles.bodyLarge.copyWith(
                                  color: subscriptionService.hasPremiumAccess
                                      ? VlvtColors.success
                                      : VlvtColors.crimson,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: subscriptionService.hasPremiumAccess
                                ? VlvtButton.secondary(
                                    label: 'Manage Subscription',
                                    icon: Icons.settings,
                                    onPressed: () {
                                      subscriptionService.presentCustomerCenter(context);
                                    },
                                  )
                                : VlvtButton.primary(
                                    label: 'Upgrade to Premium',
                                    icon: Icons.star,
                                    expanded: true,
                                    onPressed: () async {
                                      await subscriptionService.presentPaywallIfNeeded();
                                    },
                                  ),
                          ),
                          if (!subscriptionService.hasPremiumAccess) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: VlvtButton.text(
                                label: 'Restore Purchases',
                                onPressed: () async {
                                  final restored = await subscriptionService.restorePurchases();
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(restored
                                            ? 'Purchases restored successfully!'
                                            : 'No purchases to restore'),
                                        backgroundColor: VlvtColors.surface,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    VlvtCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Profile Information',
                            style: VlvtTextStyles.h3.copyWith(color: VlvtColors.gold),
                          ),
                          const SizedBox(height: 12),
                          if (profile?.age != null) ...[
                            _buildInfoRow('Age', profile!.age.toString()),
                            Divider(color: VlvtColors.borderSubtle),
                          ],
                          if (profile?.bio != null) ...[
                            _buildInfoRow('Bio', profile!.bio!),
                            Divider(color: VlvtColors.borderSubtle),
                          ],
                          if (profile?.interests != null && profile!.interests!.isNotEmpty)
                            _buildInfoRow('Interests', profile.interests!.join(', ')),
                          if (!_hasProfileInfo(profile))
                            Text(
                              'No profile information available',
                              style: VlvtTextStyles.bodyMedium.copyWith(color: VlvtColors.textMuted),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    VlvtButton.primary(
                      label: 'Edit Profile',
                      icon: Icons.edit,
                      expanded: true,
                      onPressed: () => _navigateToEditProfile(profile),
                    ),
                    const SizedBox(height: 12),
                    VlvtButton.secondary(
                      label: 'Safety & Privacy',
                      icon: Icons.security,
                      expanded: true,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const SafetySettingsScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    VlvtButton.secondary(
                      label: 'Invite Friends',
                      icon: Icons.confirmation_number,
                      expanded: true,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const InviteScreen(),
                          ),
                        );
                      },
                    ),
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

  Widget _buildProfileCompletionBanner() {
    final missingFields = List<String>.from(_profileCompletionStatus?['missingFields'] ?? []);
    final message = _profileCompletionStatus?['message'] as String? ?? 'Please complete your profile to start messaging';
    final needsIdVerification = missingFields.contains('id_verification');
    final userId = context.read<AuthService>().userId;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VlvtColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VlvtColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: VlvtColors.error, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Profile Incomplete',
                  style: VlvtTextStyles.h3.copyWith(color: VlvtColors.error),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: VlvtTextStyles.bodyMedium.copyWith(color: VlvtColors.error),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: VlvtButton.secondary(
                  label: 'Edit Profile',
                  icon: Icons.edit,
                  onPressed: () {
                    final profileService = context.read<ProfileApiService>();
                    profileService.getProfile(userId!).then((profile) {
                      _navigateToEditProfile(profile);
                    });
                  },
                ),
              ),
              if (needsIdVerification) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: VlvtButton.primary(
                    label: 'Verify ID',
                    icon: Icons.verified_user,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const IdVerificationScreen(),
                        ),
                      ).then((_) {
                        _refreshProfile();
                      });
                    },
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: VlvtTextStyles.labelMedium.copyWith(
              color: VlvtColors.textMuted,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              style: VlvtTextStyles.bodyMedium.copyWith(
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
