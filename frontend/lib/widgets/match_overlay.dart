import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Elegant match feedback overlay that replaces intrusive Snackbars
class MatchOverlay extends StatefulWidget {
  final String userName;
  final bool isNewMatch;
  final VoidCallback onDismiss;

  const MatchOverlay({
    super.key,
    required this.userName,
    required this.isNewMatch,
    required this.onDismiss,
  });

  @override
  State<MatchOverlay> createState() => _MatchOverlayState();
}

class _MatchOverlayState extends State<MatchOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 10,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.8)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_controller);

    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.0),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0),
        weight: 20,
      ),
    ]).animate(_controller);

    _controller.forward().then((_) {
      widget.onDismiss();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        _controller.animateTo(1.0, duration: const Duration(milliseconds: 300));
      },
      child: Container(
        color: Colors.transparent,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: child,
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: widget.isNewMatch
                      ? [Colors.pink.shade400, Colors.red.shade400]
                      : [Colors.orange.shade400, Colors.amber.shade400],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: (widget.isNewMatch ? Colors.pink : Colors.orange)
                        .withAlpha(128),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.isNewMatch ? Icons.favorite : Icons.info_outline,
                    color: Colors.white,
                    size: 64,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.isNewMatch ? "It's a Match!" : 'Already Matched!',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.isNewMatch
                        ? 'You and ${widget.userName} liked each other!'
                        : 'You already matched with ${widget.userName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Heart particles that fly up when liking a profile
class HeartParticleAnimation extends StatefulWidget {
  final VoidCallback onComplete;

  const HeartParticleAnimation({
    super.key,
    required this.onComplete,
  });

  @override
  State<HeartParticleAnimation> createState() => _HeartParticleAnimationState();
}

class _HeartParticleAnimationState extends State<HeartParticleAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_Particle> _particles = [];
  final math.Random _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Generate random particles
    for (int i = 0; i < 15; i++) {
      _particles.add(_Particle(
        startX: 0.4 + (_random.nextDouble() * 0.2), // Center-ish
        endX: _random.nextDouble(),
        startY: 0.5,
        endY: -0.2,
        size: 20 + (_random.nextDouble() * 20),
        rotation: _random.nextDouble() * math.pi * 2,
      ));
    }

    _controller.forward().then((_) {
      widget.onComplete();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: _particles.map((particle) {
              final progress = _controller.value;
              final x = particle.startX + (particle.endX - particle.startX) * progress;
              final y = particle.startY + (particle.endY - particle.startY) * progress;
              final opacity = (1.0 - progress).clamp(0.0, 1.0);

              return Positioned(
                left: x * size.width - particle.size / 2,
                top: y * size.height - particle.size / 2,
                child: Transform.rotate(
                  angle: particle.rotation * progress,
                  child: Opacity(
                    opacity: opacity,
                    child: Icon(
                      Icons.favorite,
                      color: Colors.pink.shade300,
                      size: particle.size,
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _Particle {
  final double startX;
  final double endX;
  final double startY;
  final double endY;
  final double size;
  final double rotation;

  _Particle({
    required this.startX,
    required this.endX,
    required this.startY,
    required this.endY,
    required this.size,
    required this.rotation,
  });
}
