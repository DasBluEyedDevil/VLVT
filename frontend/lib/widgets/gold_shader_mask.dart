import 'package:flutter/material.dart';
import '../theme/vlvt_colors.dart';

/// GoldShaderMask - Applies a metallic gold gradient effect to child widgets
///
/// Commonly used for:
/// - Navigation bar icons
/// - Premium feature highlights
/// - Active state indicators
/// - Title text with metallic sheen
///
/// Usage:
/// ```dart
/// GoldShaderMask(
///   child: Icon(Icons.star, color: Colors.white),
/// )
/// ```
class GoldShaderMask extends StatelessWidget {
  final Widget child;

  /// Whether to animate the gradient for a subtle shimmer effect
  final bool animated;

  /// Blend mode for the shader (default: srcIn works best for icons/text)
  final BlendMode blendMode;

  /// Gradient direction
  final _GradientDirection _direction;

  const GoldShaderMask({
    super.key,
    required this.child,
    this.animated = false,
    this.blendMode = BlendMode.srcIn,
  }) : _direction = _GradientDirection.diagonal;

  const GoldShaderMask._horizontal({
    super.key,
    required this.child,
    this.blendMode = BlendMode.srcIn,
  })  : animated = false,
        _direction = _GradientDirection.horizontal;

  const GoldShaderMask._radial({
    super.key,
    required this.child,
    this.blendMode = BlendMode.srcIn,
  })  : animated = false,
        _direction = _GradientDirection.radial;

  /// Static constructor for horizontal metallic gradient
  static Widget horizontal({
    Key? key,
    required Widget child,
    BlendMode blendMode = BlendMode.srcIn,
  }) {
    return GoldShaderMask._horizontal(
      key: key,
      blendMode: blendMode,
      child: child,
    );
  }

  /// Static constructor for radial metallic gradient (good for circular icons)
  static Widget radial({
    Key? key,
    required Widget child,
    BlendMode blendMode = BlendMode.srcIn,
  }) {
    return GoldShaderMask._radial(
      key: key,
      blendMode: blendMode,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (animated) {
      return _AnimatedGoldShaderMask(
        blendMode: blendMode,
        child: child,
      );
    }

    return ShaderMask(
      blendMode: blendMode,
      shaderCallback: (Rect bounds) {
        return _createGradient().createShader(bounds);
      },
      child: child,
    );
  }

  Gradient _createGradient() {
    switch (_direction) {
      case _GradientDirection.diagonal:
        return const LinearGradient(
          colors: [
            VlvtColors.gold,
            VlvtColors.goldLight,
            VlvtColors.gold,
          ],
          stops: [0.0, 0.5, 1.0],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case _GradientDirection.horizontal:
        return const LinearGradient(
          colors: [
            VlvtColors.gold,
            VlvtColors.goldLight,
            VlvtColors.gold,
          ],
          stops: [0.0, 0.5, 1.0],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        );
      case _GradientDirection.radial:
        return const RadialGradient(
          colors: [
            VlvtColors.goldLight,
            VlvtColors.gold,
            VlvtColors.goldDark,
          ],
          stops: [0.0, 0.6, 1.0],
          center: Alignment.center,
          radius: 1.0,
        );
    }
  }
}

enum _GradientDirection { diagonal, horizontal, radial }

/// Animated shimmer version
class _AnimatedGoldShaderMask extends StatefulWidget {
  final Widget child;
  final BlendMode blendMode;

  const _AnimatedGoldShaderMask({
    required this.child,
    required this.blendMode,
  });

  @override
  State<_AnimatedGoldShaderMask> createState() =>
      _AnimatedGoldShaderMaskState();
}

class _AnimatedGoldShaderMaskState extends State<_AnimatedGoldShaderMask>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: widget.blendMode,
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              colors: const [
                VlvtColors.gold,
                VlvtColors.goldLight,
                VlvtColors.gold,
                VlvtColors.goldLight,
                VlvtColors.gold,
              ],
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              begin: Alignment(-1.5 + _controller.value * 3, -0.5),
              end: Alignment(-0.5 + _controller.value * 3, 0.5),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}
