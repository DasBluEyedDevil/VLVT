import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Tutorial overlay that shows users how to use swipe gestures
/// on the Discovery screen
class SwipeTutorialOverlay extends StatefulWidget {
  final VoidCallback onDismiss;

  const SwipeTutorialOverlay({
    super.key,
    required this.onDismiss,
  });

  @override
  State<SwipeTutorialOverlay> createState() => _SwipeTutorialOverlayState();
}

class _SwipeTutorialOverlayState extends State<SwipeTutorialOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismiss() {
    HapticFeedback.lightImpact();
    _animationController.reverse().then((_) {
      widget.onDismiss();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black87,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Stack(
            children: [
              // Dismissible background
              Positioned.fill(
                child: GestureDetector(
                  onTap: _dismiss,
                  behavior: HitTestBehavior.opaque,
                  child: const SizedBox.expand(),
                ),
              ),

              // Tutorial content
              Center(
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title
                        const Text(
                          'Welcome to Discovery!',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),

                        // Swipe instructions with animations
                        _buildSwipeInstruction(
                          icon: Icons.arrow_forward,
                          color: Colors.green,
                          label: 'Swipe Right',
                          description: 'to LIKE',
                          delay: 0,
                        ),
                        const SizedBox(height: 24),

                        _buildSwipeInstruction(
                          icon: Icons.arrow_back,
                          color: Colors.red,
                          label: 'Swipe Left',
                          description: 'to PASS',
                          delay: 200,
                        ),
                        const SizedBox(height: 24),

                        _buildSwipeInstruction(
                          icon: Icons.touch_app,
                          color: Colors.blue,
                          label: 'Tap Card',
                          description: 'to see more details',
                          delay: 400,
                        ),
                        const SizedBox(height: 40),

                        // Dismiss button
                        ElevatedButton(
                          onPressed: _dismiss,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 48,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text(
                            'Got It!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Tap anywhere to dismiss',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwipeInstruction({
    required IconData icon,
    required Color color,
    required String label,
    required String description,
    required int delay,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 400 + delay),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withOpacity(0.3),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: color,
              size: 40,
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
