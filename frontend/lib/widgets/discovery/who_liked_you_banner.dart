import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/vlvt_colors.dart';

/// A banner widget showing the count of users who have liked the current user
/// Tapping navigates to the "Who Liked You" screen
class WhoLikedYouBanner extends StatelessWidget {
  final int likesCount;
  final VoidCallback onTap;

  const WhoLikedYouBanner({
    super.key,
    required this.likesCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (likesCount <= 0) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              VlvtColors.gold.withValues(alpha: 0.2),
              VlvtColors.gold.withValues(alpha: 0.1),
            ],
          ),
          border: Border(
            bottom: BorderSide(
              color: VlvtColors.gold.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: VlvtColors.gold,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$likesCount',
                style: TextStyle(
                  color: VlvtColors.textOnGold,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Montserrat',
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$likesCount ${likesCount == 1 ? 'person' : 'people'} liked you',
                    style: TextStyle(
                      color: VlvtColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Montserrat',
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    "See who's already interested",
                    style: TextStyle(
                      color: VlvtColors.textSecondary,
                      fontFamily: 'Montserrat',
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              color: VlvtColors.gold,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}
