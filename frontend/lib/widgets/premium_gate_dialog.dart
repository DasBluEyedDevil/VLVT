import 'package:flutter/material.dart';
import '../screens/paywall_screen.dart';

class PremiumGateDialog extends StatelessWidget {
  final String title;
  final String message;
  final String benefit;
  final IconData icon;

  const PremiumGateDialog({
    super.key,
    required this.title,
    required this.message,
    required this.benefit,
    this.icon = Icons.lock,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 48,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.star,
                    color: Colors.amber,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      benefit,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // Use RevenueCat's native paywall if configured, otherwise fallback to custom
                  await PaywallScreen.show(context, source: 'premium_gate');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Continue with Premium',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                'Maybe Later',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Convenience factory methods for common scenarios
  static void showLikesLimitReached(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PremiumGateDialog(
        title: 'Premium Required',
        message: 'Subscribe to start liking profiles and making connections.',
        benefit: 'Unlimited likes to find your perfect match!',
        icon: Icons.favorite,
      ),
    );
  }

  static void showMessagesLimitReached(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PremiumGateDialog(
        title: 'Premium Required',
        message: 'Subscribe to send messages and chat with your matches.',
        benefit: 'Unlimited messaging with all your matches!',
        icon: Icons.chat,
      ),
    );
  }

  static void showSwipingRequired(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const PremiumGateDialog(
        title: 'Premium Required',
        message: 'Subscribe to swipe on profiles and find your matches.',
        benefit: 'Unlimited swiping to discover compatible people!',
        icon: Icons.swipe,
      ),
    );
  }

  static void showFeatureBlocked(
    BuildContext context, {
    required String title,
    required String message,
    required String benefit,
    IconData icon = Icons.lock,
  }) {
    showDialog(
      context: context,
      builder: (context) => PremiumGateDialog(
        title: title,
        message: message,
        benefit: benefit,
        icon: icon,
      ),
    );
  }
}
