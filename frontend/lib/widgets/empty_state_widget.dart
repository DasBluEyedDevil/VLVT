import 'package:flutter/material.dart';

/// Enhanced empty state widget with icons, helpful messaging, and CTAs
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final Color? iconColor;
  final double iconSize;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.iconColor,
    this.iconSize = 100.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated icon with subtle pulse effect
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.9, end: 1.0),
              duration: const Duration(milliseconds: 1500),
              curve: Curves.easeInOut,
              builder: (context, scale, child) {
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: (iconColor ?? theme.colorScheme.primary)
                          .withAlpha(isDark ? 38 : 26),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: iconSize,
                      color: iconColor ?? theme.colorScheme.primary,
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 32),

            // Title
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.textTheme.bodyLarge?.color,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 12),

            // Message
            Text(
              message,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.textTheme.bodyMedium?.color,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 32),

            // Primary action button
            if (actionLabel != null && onAction != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onAction,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(actionLabel!),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

            // Secondary action button
            if (secondaryActionLabel != null && onSecondaryAction != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onSecondaryAction,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(secondaryActionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Specific empty states for common scenarios
class DiscoveryEmptyState {
  static Widget noProfiles({
    required BuildContext context,
    required bool hasFilters,
    required VoidCallback onAdjustFilters,
    required VoidCallback onShowAllProfiles,
  }) {
    return EmptyStateWidget(
      icon: Icons.explore_outlined,
      iconColor: Colors.deepPurple,
      title: hasFilters ? 'No profiles match your filters' : 'No more profiles',
      message: hasFilters
          ? 'Try adjusting your age range, distance, or interests to discover more people.'
          : 'You\'ve seen all available profiles! Check back later for new matches, or reset to see profiles again.',
      actionLabel: hasFilters ? 'Adjust Filters' : 'Show All Profiles Again',
      onAction: hasFilters ? onAdjustFilters : onShowAllProfiles,
      secondaryActionLabel: hasFilters ? 'Show All Profiles' : null,
      onSecondaryAction: hasFilters ? onShowAllProfiles : null,
    );
  }
}

class MatchesEmptyState {
  static Widget noMatches({
    required VoidCallback onGoToDiscovery,
  }) {
    return EmptyStateWidget(
      icon: Icons.favorite_border_rounded,
      iconColor: Colors.pink,
      iconSize: 120,
      title: 'No matches yet',
      message: 'Start swiping in the Discovery tab to find people you like. When you both like each other, you\'ll match!',
      actionLabel: 'Go to Discovery',
      onAction: onGoToDiscovery,
    );
  }

  static Widget noSearchResults() {
    return const EmptyStateWidget(
      icon: Icons.search_off_rounded,
      iconColor: Colors.grey,
      title: 'No matches found',
      message: 'Try adjusting your search terms or clear filters to see all your matches.',
    );
  }
}

class ChatEmptyState {
  static Widget noMessages({
    required String matchedUserName,
  }) {
    return EmptyStateWidget(
      icon: Icons.chat_bubble_outline_rounded,
      iconColor: Colors.blue,
      title: 'Start the conversation!',
      message: 'You matched with $matchedUserName. Say hi and break the ice!',
    );
  }
}
