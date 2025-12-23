import 'package:flutter/material.dart';
import '../../theme/vlvt_colors.dart';

/// An animated hint indicator that shows users how to swipe
/// Used for first-time users who haven't completed the tutorial
class SwipeHintIndicator extends StatefulWidget {
  const SwipeHintIndicator({super.key});

  @override
  State<SwipeHintIndicator> createState() => _SwipeHintIndicatorState();
}

class _SwipeHintIndicatorState extends State<SwipeHintIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);

    _animation = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.arrow_back,
            color: VlvtColors.crimson.withValues(alpha: 0.6),
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Swipe to interact',
            style: TextStyle(
              fontSize: 14,
              color: VlvtColors.textSecondary.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.arrow_forward,
            color: VlvtColors.success.withValues(alpha: 0.6),
            size: 20,
          ),
        ],
      ),
    );
  }
}
