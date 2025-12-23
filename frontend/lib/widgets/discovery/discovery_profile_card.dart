import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/profile.dart';
import '../../services/profile_api_service.dart';
import '../../services/location_service.dart';
import '../../theme/vlvt_colors.dart';
import '../../theme/vlvt_text_styles.dart';
import '../verified_badge.dart';

/// A reusable profile card widget for the discovery screen
/// Displays profile photo carousel, name, age, bio, and interests
class DiscoveryProfileCard extends StatelessWidget {
  final Profile profile;
  final int currentPhotoIndex;
  final PageController? photoPageController;
  final bool isExpanded;
  final Alignment parallaxAlignment;
  final ValueChanged<int>? onPhotoChanged;
  final VoidCallback? onInitPhotoController;

  const DiscoveryProfileCard({
    super.key,
    required this.profile,
    required this.currentPhotoIndex,
    this.photoPageController,
    this.isExpanded = false,
    this.parallaxAlignment = Alignment.center,
    this.onPhotoChanged,
    this.onInitPhotoController,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      color: VlvtColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: VlvtColors.gold.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              VlvtColors.primary.withValues(alpha: 0.4),
              VlvtColors.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Photo carousel or default icon
                if (profile.photos != null && profile.photos!.isNotEmpty) ...[
                  Builder(
                    builder: (context) {
                      onInitPhotoController?.call();
                      return Column(
                        children: [
                          SizedBox(
                            height: 300,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: PageView.builder(
                                controller: photoPageController,
                                onPageChanged: (index) {
                                  HapticFeedback.selectionClick();
                                  onPhotoChanged?.call(index);
                                },
                                itemCount: profile.photos!.length,
                                itemBuilder: (context, index) {
                                  final photoUrl = profile.photos![index];
                                  final profileService = context.read<ProfileApiService>();
                                  return Hero(
                                    tag: 'discovery_${profile.userId}',
                                    child: CachedNetworkImage(
                                      imageUrl: photoUrl.startsWith('http')
                                          ? photoUrl
                                          : '${profileService.baseUrl}$photoUrl',
                                      fit: BoxFit.cover,
                                      alignment: parallaxAlignment,
                                      memCacheWidth: 800,
                                      placeholder: (context, url) => Container(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        child: const Icon(
                                          Icons.broken_image,
                                          size: 80,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          if (profile.photos!.length > 1) ...[
                            const SizedBox(height: 12),
                            _PhotoIndicators(
                              count: profile.photos!.length,
                              currentIndex: currentPhotoIndex,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ] else
                  const Icon(
                    Icons.person,
                    size: 120,
                    color: Colors.white,
                  ),
                const SizedBox(height: 24),
                _ProfileHeader(profile: profile),
                const SizedBox(height: 16),
                Text(
                  profile.bio ?? 'No bio available',
                  textAlign: TextAlign.center,
                  style: VlvtTextStyles.bodyLarge.copyWith(
                    color: VlvtColors.textSecondary,
                  ),
                ),
                if (profile.interests != null && profile.interests!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Divider(color: VlvtColors.gold.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  _InterestsSection(interests: profile.interests!),
                ],
                if (isExpanded) ...[
                  const SizedBox(height: 24),
                  Divider(color: VlvtColors.gold.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  _ExpandedInfo(profile: profile),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoIndicators extends StatelessWidget {
  final int count;
  final int currentIndex;

  const _PhotoIndicators({
    required this.count,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (index) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: currentIndex == index
                ? Colors.white
                : Colors.white.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final Profile profile;

  const _ProfileHeader({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '${profile.name ?? 'Anonymous'}, ${profile.age ?? '?'}',
          style: VlvtTextStyles.displayMedium.copyWith(
            color: VlvtColors.textPrimary,
          ),
        ),
        if (profile.isVerified) ...[
          const SizedBox(width: 8),
          const VerifiedIcon(size: 24),
        ],
      ],
    );
  }
}

class _InterestsSection extends StatelessWidget {
  final List<String> interests;

  const _InterestsSection({required this.interests});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Interests',
          style: VlvtTextStyles.h3.copyWith(
            color: VlvtColors.gold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: interests.map((interest) {
            return Chip(
              label: Text(interest),
              backgroundColor: VlvtColors.gold.withValues(alpha: 0.15),
              labelStyle: VlvtTextStyles.labelSmall.copyWith(
                color: VlvtColors.gold,
              ),
              side: BorderSide(
                color: VlvtColors.gold.withValues(alpha: 0.3),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ExpandedInfo extends StatelessWidget {
  final Profile profile;

  const _ExpandedInfo({required this.profile});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, color: VlvtColors.textSecondary, size: 20),
            const SizedBox(width: 8),
            Text(
              'More Info',
              style: VlvtTextStyles.labelMedium.copyWith(
                color: VlvtColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          profile.distance != null
              ? 'Distance: ${LocationService.formatDistance(profile.distance! * 1000)}'
              : 'Distance: Not available',
          style: VlvtTextStyles.bodyMedium.copyWith(color: VlvtColors.textSecondary),
        ),
        const SizedBox(height: 8),
        Text(
          'Tap card to collapse',
          style: VlvtTextStyles.bodySmall.copyWith(color: VlvtColors.textMuted),
        ),
      ],
    );
  }
}
