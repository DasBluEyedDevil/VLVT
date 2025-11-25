import 'dart:async';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../constants/spacing.dart';
import '../constants/text_styles.dart';

/// Banner widget that displays when the app is offline
class OfflineBanner extends StatelessWidget {
  final bool isOffline;
  final VoidCallback? onRetry;

  const OfflineBanner({
    super.key,
    required this.isOffline,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (!isOffline) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: isOffline ? 48 : 0,
      child: Material(
        color: AppColors.error(context),
        child: SafeArea(
          bottom: false,
          child: Container(
            padding: Spacing.horizontalPaddingMd,
            child: Row(
              children: [
                const Icon(
                  Icons.cloud_off,
                  color: Colors.white,
                  size: 20,
                ),
                Spacing.horizontalSm,
                Expanded(
                  child: Text(
                    'You\'re offline',
                    style: AppTextStyles.labelMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Retry'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Widget that wraps content and shows offline banner
class OfflineWrapper extends StatefulWidget {
  final Widget child;
  final VoidCallback? onRetry;

  const OfflineWrapper({
    super.key,
    required this.child,
    this.onRetry,
  });

  @override
  State<OfflineWrapper> createState() => _OfflineWrapperState();
}

class _OfflineWrapperState extends State<OfflineWrapper> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _listenToConnectivity();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result);
  }

  void _listenToConnectivity() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectionStatus,
    );
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final wasOffline = _isOffline;
    final isOffline = results.isEmpty ||
        results.every((result) => result == ConnectivityResult.none);

    if (mounted) {
      setState(() {
        _isOffline = isOffline;
      });

      // Show snackbar when connection is restored
      if (wasOffline && !isOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.cloud_done, color: Colors.white),
                SizedBox(width: 8),
                Text('Back online'),
              ],
            ),
            backgroundColor: AppColors.success(context),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        OfflineBanner(
          isOffline: _isOffline,
          onRetry: widget.onRetry ?? _checkConnectivity,
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

/// Mixin to add connectivity checking to any StatefulWidget
mixin ConnectivityMixin<T extends StatefulWidget> on State<T> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOffline = false;

  bool get isOffline => _isOffline;

  @override
  void initState() {
    super.initState();
    initConnectivity();
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  void initConnectivity() {
    _checkConnectivity();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectionStatus,
    );
  }

  Future<void> _checkConnectivity() async {
    final result = await _connectivity.checkConnectivity();
    _updateConnectionStatus(result);
  }

  void _updateConnectionStatus(List<ConnectivityResult> results) {
    final isOffline = results.isEmpty ||
        results.every((result) => result == ConnectivityResult.none);

    if (mounted) {
      setState(() {
        _isOffline = isOffline;
      });
      onConnectivityChanged(isOffline);
    }
  }

  /// Override this to handle connectivity changes
  void onConnectivityChanged(bool isOffline) {
    // Default implementation - can be overridden
  }

  /// Check if device is currently online
  Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return result.isNotEmpty &&
        result.any((r) => r != ConnectivityResult.none);
  }
}

/// Simple connectivity checker utility
class ConnectivityChecker {
  static final Connectivity _connectivity = Connectivity();

  /// Check if device is currently online
  static Future<bool> isOnline() async {
    final result = await _connectivity.checkConnectivity();
    return result.isNotEmpty &&
        result.any((r) => r != ConnectivityResult.none);
  }

  /// Get a stream of connectivity changes
  static Stream<List<ConnectivityResult>> get connectivityStream =>
      _connectivity.onConnectivityChanged;

  /// Check connectivity and show appropriate message
  static Future<bool> checkAndNotify(BuildContext context) async {
    final online = await isOnline();
    if (!online && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.cloud_off, color: Colors.white),
              SizedBox(width: 8),
              Text('No internet connection'),
            ],
          ),
          backgroundColor: AppColors.error(context),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
    }
    return online;
  }
}
