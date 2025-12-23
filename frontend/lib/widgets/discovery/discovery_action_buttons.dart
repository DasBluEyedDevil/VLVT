import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/vlvt_colors.dart';

/// Action buttons for the discovery screen (pass, undo, like)
/// Made semi-transparent to encourage swiping
class DiscoveryActionButtons extends StatelessWidget {
  final bool showUndoButton;
  final bool hasPremiumAccess;
  final VoidCallback onPass;
  final VoidCallback onLike;
  final VoidCallback onUndo;
  final VoidCallback onPremiumRequired;

  const DiscoveryActionButtons({
    super.key,
    required this.showUndoButton,
    required this.hasPremiumAccess,
    required this.onPass,
    required this.onLike,
    required this.onUndo,
    required this.onPremiumRequired,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Pass button - smaller and semi-transparent
          Opacity(
            opacity: 0.7,
            child: FloatingActionButton(
              heroTag: 'pass',
              mini: true,
              onPressed: () {
                if (!hasPremiumAccess) {
                  HapticFeedback.heavyImpact();
                  onPremiumRequired();
                  return;
                }
                HapticFeedback.lightImpact();
                onPass();
              },
              backgroundColor: VlvtColors.crimson,
              child: const Icon(Icons.close, size: 24, color: Colors.white),
            ),
          ),
          if (showUndoButton)
            FloatingActionButton(
              heroTag: 'undo',
              mini: true,
              onPressed: () {
                HapticFeedback.lightImpact();
                onUndo();
              },
              backgroundColor: VlvtColors.primary,
              child: const Icon(Icons.undo, size: 20, color: Colors.white),
            ),
          // Like button - smaller and semi-transparent
          Opacity(
            opacity: 0.7,
            child: FloatingActionButton(
              heroTag: 'like',
              mini: true,
              onPressed: () {
                if (!hasPremiumAccess) {
                  HapticFeedback.heavyImpact();
                  onPremiumRequired();
                  return;
                }
                HapticFeedback.mediumImpact();
                onLike();
              },
              backgroundColor: VlvtColors.success,
              child: const Icon(Icons.favorite, size: 24, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
