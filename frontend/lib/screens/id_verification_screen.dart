import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/auth_service.dart';
import '../theme/vlvt_colors.dart';
import '../theme/vlvt_text_styles.dart';
import '../widgets/vlvt_button.dart';

/// ID Verification Screen using KYCAID
///
/// This screen handles government ID verification (Option B paywall):
/// Users must verify their ID before they can create a profile and use the app.
class IdVerificationScreen extends StatefulWidget {
  const IdVerificationScreen({super.key});

  @override
  State<IdVerificationScreen> createState() => _IdVerificationScreenState();
}

class _IdVerificationScreenState extends State<IdVerificationScreen> {
  bool _isLoading = true;
  bool _isStarting = false;
  String? _errorMessage;
  bool _showWebView = false;
  bool _isVerified = false;
  bool _isPending = false;
  Timer? _pollingTimer;
  WebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _checkVerificationStatus();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkVerificationStatus() async {
    final authService = context.read<AuthService>();
    final result = await authService.getIdVerificationStatus();

    if (!mounted) return;

    if (result['success'] == true) {
      if (result['verified'] == true) {
        setState(() {
          _isLoading = false;
          _isVerified = true;
        });
        // Auto-navigate after showing success
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        });
      } else if (result['verificationStatus'] == 'declined') {
        // Previous verification was declined - allow retry
        setState(() {
          _isLoading = false;
          _errorMessage = 'Your previous verification was declined. Please try again with a valid ID.';
        });
      } else if (result['status'] == 'pending' || result['verificationStatus'] == 'pending') {
        setState(() {
          _isLoading = false;
          _isPending = true;
        });
        // Start polling for status updates
        _startPolling();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = result['error'] as String?;
      });
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    // Capture AuthService reference outside the timer callback to avoid
    // accessing context after widget is disposed
    final authService = context.read<AuthService>();

    _pollingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      // Check mounted BEFORE doing any work to avoid accessing disposed context
      if (!mounted) {
        timer.cancel();
        return;
      }

      final result = await authService.getIdVerificationStatus();

      // Check mounted again after async operation
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (result['verified'] == true) {
        timer.cancel();
        setState(() {
          _isVerified = true;
          _isPending = false;
        });
        // Auto-navigate after showing success
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        });
      } else if (result['verificationStatus'] == 'declined') {
        timer.cancel();
        setState(() {
          _isPending = false;
          _errorMessage = 'Verification was declined. Please try again with a valid ID.';
        });
      }
    });
  }

  Future<void> _startVerification() async {
    setState(() {
      _isStarting = true;
      _errorMessage = null;
    });

    final authService = context.read<AuthService>();
    final result = await authService.startIdVerification();

    if (!mounted) return;

    if (result['success'] == true) {
      if (result['alreadyVerified'] == true) {
        setState(() {
          _isStarting = false;
          _isVerified = true;
        });
        // Auto-navigate after showing success
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        });
      } else {
        final verificationId = result['verificationId'] as String?;
        if (verificationId != null) {
          setState(() {
            _isStarting = false;
          });
          _openVerificationWebView(authService.getKycaidVerificationUrl(verificationId));
        } else {
          setState(() {
            _isStarting = false;
            _errorMessage = 'Failed to get verification ID';
          });
        }
      }
    } else {
      setState(() {
        _isStarting = false;
        _errorMessage = result['error'] as String? ?? 'Failed to start verification';
      });
    }
  }

  void _openVerificationWebView(String url) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(VlvtColors.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('WebView loading: $url');
          },
          onPageFinished: (String url) {
            debugPrint('WebView finished: $url');
            // Check if verification completed (user closed the verification flow)
            if (url.contains('verification-completed') ||
                url.contains('success') ||
                url.contains('callback')) {
              _onVerificationFlowCompleted();
            }
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    setState(() {
      _showWebView = true;
    });
  }

  void _onVerificationFlowCompleted() {
    setState(() {
      _showWebView = false;
      _isPending = true;
    });
    _startPolling();
  }

  void _closeWebView() {
    setState(() {
      _showWebView = false;
      _isPending = true;
    });
    // Start polling to check if they completed verification
    _startPolling();
  }

  @override
  Widget build(BuildContext context) {
    if (_showWebView && _webViewController != null) {
      return Scaffold(
        backgroundColor: VlvtColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: VlvtColors.textPrimary),
            onPressed: _closeWebView,
          ),
          title: Text(
            'Verify Your ID',
            style: VlvtTextStyles.h3.copyWith(color: VlvtColors.textPrimary),
          ),
          centerTitle: true,
        ),
        body: WebViewWidget(controller: _webViewController!),
      );
    }

    return Scaffold(
      backgroundColor: VlvtColors.background,
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: VlvtColors.gold),
              )
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_isVerified) {
      return _buildVerifiedState();
    }

    if (_isPending) {
      return _buildPendingState();
    }

    return _buildInitialState();
  }

  Widget _buildInitialState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height -
              MediaQuery.of(context).padding.top -
              MediaQuery.of(context).padding.bottom -
              48, // Account for padding
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 40),

            // Icon
            Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: VlvtColors.gold.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.badge_outlined,
              size: 60,
              color: VlvtColors.gold,
            ),
          ),

          const SizedBox(height: 32),

          // Title
          Text(
            'Verify Your Identity',
            style: VlvtTextStyles.h1.copyWith(color: VlvtColors.textPrimary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          // Subtitle
          Text(
            'To keep VLVT safe and exclusive, we need to verify your government-issued ID.',
            style: VlvtTextStyles.bodyLarge.copyWith(color: VlvtColors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 40),

          // Requirements list
          _buildRequirementItem(
            icon: Icons.credit_card,
            title: 'Valid Government ID',
            subtitle: 'Driver\'s license, passport, or national ID card',
          ),
          const SizedBox(height: 16),
          _buildRequirementItem(
            icon: Icons.face,
            title: 'Quick Selfie',
            subtitle: 'To match your face with your ID photo',
          ),
          const SizedBox(height: 16),
          _buildRequirementItem(
            icon: Icons.lock_outline,
            title: 'Secure & Private',
            subtitle: 'Your data is encrypted and never shared',
          ),

          const SizedBox(height: 40),

          // Error message
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(16),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: VlvtColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: VlvtColors.error),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: VlvtTextStyles.bodySmall.copyWith(color: VlvtColors.error),
                    ),
                  ),
                ],
              ),
            ),

          // Start button
          VlvtButton.primary(
            label: _isStarting ? 'Starting...' : 'Start Verification',
            onPressed: _isStarting ? null : _startVerification,
            icon: Icons.verified_user,
            expanded: true,
          ),

          const SizedBox(height: 16),

          // Info text
          Text(
            'Takes about 2 minutes',
            style: VlvtTextStyles.caption.copyWith(color: VlvtColors.textMuted),
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildRequirementItem({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VlvtColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: VlvtColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: VlvtColors.gold),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: VlvtTextStyles.bodyMedium.copyWith(
                    color: VlvtColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: VlvtTextStyles.caption.copyWith(
                    color: VlvtColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated loading indicator
          const SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              color: VlvtColors.gold,
              strokeWidth: 4,
            ),
          ),

          const SizedBox(height: 32),

          Text(
            'Verification in Progress',
            style: VlvtTextStyles.h2.copyWith(color: VlvtColors.textPrimary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Text(
            'We\'re reviewing your documents. This usually takes just a minute.',
            style: VlvtTextStyles.bodyLarge.copyWith(color: VlvtColors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 40),

          // Manual refresh button
          VlvtButton.secondary(
            label: 'Check Status',
            onPressed: _checkVerificationStatus,
            icon: Icons.refresh,
          ),
        ],
      ),
    );
  }

  Widget _buildVerifiedState() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Success icon
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: VlvtColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              size: 80,
              color: VlvtColors.success,
            ),
          ),

          const SizedBox(height: 32),

          Text(
            'Verified!',
            style: VlvtTextStyles.h1.copyWith(color: VlvtColors.success),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 16),

          Text(
            'Your identity has been verified. You can now create your profile and start meeting people.',
            style: VlvtTextStyles.bodyLarge.copyWith(color: VlvtColors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 40),

          VlvtButton.primary(
            label: 'Continue',
            onPressed: () => Navigator.of(context).pop(true),
            icon: Icons.arrow_forward,
            expanded: true,
          ),
        ],
      ),
    );
  }
}
