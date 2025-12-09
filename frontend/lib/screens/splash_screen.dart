import 'package:flutter/material.dart';
import '../widgets/vlvt_background.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _fadeController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;
  bool _animationsStarted = false;

  @override
  void initState() {
    super.initState();

    // Logo scale and pulse animation
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.elasticOut,
      ),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: Curves.easeInOut,
      ),
    );

    // Fade out animation
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeOut,
      ),
    );

    // Logo animation starts immediately
    _logoController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Start the animation sequence after dependencies are available
    // This ensures context can be used for precacheImage
    _startAnimations();
  }

  Future<void> _startAnimations() async {
    // Prevent multiple calls
    if (_animationsStarted) return;
    _animationsStarted = true;

    // Pre-cache critical assets in parallel with animation
    final preCacheFuture = _preCacheAssets();

    // Wait for BOTH animation and pre-caching (with minimum display time)
    await Future.wait([
      preCacheFuture,
      Future.delayed(const Duration(milliseconds: 2000)),
    ]);

    // Fade out
    await _fadeController.forward();

    // Complete
    widget.onComplete();
  }

  /// Pre-cache heavy assets used in subsequent screens
  Future<void> _preCacheAssets() async {
    if (!mounted) return;
    try {
      await Future.wait([
        // Pre-cache the auth screen background
        precacheImage(
          const AssetImage('assets/images/loginbackground.jpg'),
          context,
        ),
        // Pre-cache the logo for other screens
        precacheImage(
          const AssetImage('assets/images/logo.png'),
          context,
        ),
      ]);
    } catch (e) {
      // Silently fail - assets will load normally if pre-cache fails
      debugPrint('Asset pre-cache failed: $e');
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: VlvtBackground(
          child: Center(
            child: AnimatedBuilder(
              animation: _logoController,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value * _pulseAnimation.value,
                  child: child,
                );
              },
              child: Image.asset(
                'assets/images/logo.png',
                width: 200,
                height: 200,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
