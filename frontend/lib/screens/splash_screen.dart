import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _hasCompleted = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _controller = VideoPlayerController.asset('assets/images/splash.mp4');

    try {
      await _controller.initialize();

      if (!mounted) return;
      setState(() => _isInitialized = true);

      debugPrint('Splash video initialized: ${_controller.value.duration}');

      // Listen for video completion
      _controller.addListener(_onVideoUpdate);

      // Start playing
      await _controller.play();
      debugPrint('Splash video playing');
    } catch (e) {
      // If video fails to load, skip splash after a short delay
      debugPrint('Splash video failed to load: $e');
      await Future.delayed(const Duration(milliseconds: 500));
      _complete();
    }
  }

  void _onVideoUpdate() {
    if (_hasCompleted) return;

    final position = _controller.value.position;
    final duration = _controller.value.duration;

    // Check if video has finished (position is at or near the end)
    if (duration.inMilliseconds > 0 &&
        position.inMilliseconds >= duration.inMilliseconds - 100) {
      debugPrint('Splash video completed');
      _complete();
    }
  }

  void _complete() {
    if (_hasCompleted) return;
    _hasCompleted = true;
    widget.onComplete();
  }

  @override
  void dispose() {
    _controller.removeListener(_onVideoUpdate);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitialized
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller.value.size.width,
                  height: _controller.value.size.height,
                  child: VideoPlayer(_controller),
                ),
              ),
            )
          : const Center(
              child: CircularProgressIndicator(
                color: Colors.white,
              ),
            ),
    );
  }
}
