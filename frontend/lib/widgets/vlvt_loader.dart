import 'package:flutter/material.dart';
import '../theme/vlvt_colors.dart';

/// A pulsating logo loader for the VLVT design system.
///
/// Displays the VLVT logo text with a breathing animation.
class VlvtLoader extends StatefulWidget {
  /// The size of the logo.
  final double size;

  /// Optional message to display below the logo.
  final String? message;

  const VlvtLoader({
    super.key,
    this.size = 120,
    this.message,
  });

  @override
  State<VlvtLoader> createState() => _VlvtLoaderState();
}

class _VlvtLoaderState extends State<VlvtLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _opacityAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _opacityAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Image.asset(
              'assets/images/vlvt_logo_text.png',
              width: widget.size,
              fit: BoxFit.contain,
            ),
          ),
        ),
        if (widget.message != null) ...[
          const SizedBox(height: 24),
          Text(
            widget.message!,
            style: TextStyle(
              color: VlvtColors.textSecondary,
              fontSize: 14,
              fontFamily: 'Montserrat',
            ),
          ),
        ],
      ],
    );
  }
}

/// A simple gold progress indicator.
class VlvtProgressIndicator extends StatelessWidget {
  /// The size of the indicator.
  final double size;

  /// The stroke width.
  final double strokeWidth;

  /// Optional value for determinate progress (0.0 to 1.0).
  final double? value;

  const VlvtProgressIndicator({
    super.key,
    this.size = 32,
    this.strokeWidth = 3,
    this.value,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: strokeWidth,
        color: VlvtColors.gold,
        backgroundColor: VlvtColors.surface,
      ),
    );
  }
}

/// A full-screen loading overlay.
class VlvtLoadingOverlay extends StatelessWidget {
  /// Whether the overlay is visible.
  final bool isLoading;

  /// The child widget to display behind the overlay.
  final Widget child;

  /// Optional message to display.
  final String? message;

  const VlvtLoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Positioned.fill(
            child: Container(
              color: VlvtColors.background.withValues(alpha: 0.8),
              child: Center(
                child: VlvtLoader(
                  message: message,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
