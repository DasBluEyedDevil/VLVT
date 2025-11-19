import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import '../services/auth_service.dart';
import '../constants/spacing.dart';
import '../constants/text_styles.dart';
import '../utils/error_handler.dart';
import 'test_login_screen.dart';
import 'legal_document_viewer.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _signInWithApple() async {
    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final success = await authService.signInWithApple();

      if (!success && mounted) {
        final error = ErrorHandler.handleError('Failed to sign in with Apple');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: AppColors.error,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _signInWithApple,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final error = ErrorHandler.handleError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(error.message, style: AppTextStyles.labelMedium),
                const SizedBox(height: 4),
                Text(error.guidance, style: AppTextStyles.caption),
              ],
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final success = await authService.signInWithGoogle();

      if (!success && mounted) {
        final error = ErrorHandler.handleError('Failed to sign in with Google');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            backgroundColor: AppColors.error,
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: _signInWithGoogle,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final error = ErrorHandler.handleError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(error.message, style: AppTextStyles.labelMedium),
                const SizedBox(height: 4),
                Text(error.guidance, style: AppTextStyles.caption),
              ],
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.primaryGradient,
            ),
          ),
          child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Padding(
                padding: Spacing.paddingLg,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo and app name
                    Container(
                      padding: Spacing.paddingXl,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite,
                        size: 100,
                        color: Colors.white,
                      ),
                    ),
                    Spacing.verticalXl,
                    Text(
                      'NoBS Dating',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.displaySmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Spacing.verticalMd,
                    Text(
                      'Straightforward dating, no BS',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.h4.copyWith(
                        color: Colors.white.withOpacity(0.9),
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    Spacing.verticalMd,
                    // Value proposition
                    Padding(
                      padding: Spacing.horizontalPaddingXl,
                      child: Text(
                        'Find meaningful connections without the games',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ),
                    Spacing.verticalXxl,
                    // Loading indicator or buttons
                    if (_isLoading)
                      Center(
                        child: Container(
                          padding: Spacing.paddingXl,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: Spacing.borderRadiusLg,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                              Spacing.verticalMd,
                              Text(
                                'Signing in...',
                                style: AppTextStyles.bodyMedium.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      // Show Sign in with Apple only on iOS
                      if (Platform.isIOS)
                        _buildAuthButton(
                          onPressed: _signInWithApple,
                          icon: Icons.apple,
                          label: 'Sign in with Apple',
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                        ),
                      if (Platform.isIOS) Spacing.verticalMd,
                      _buildAuthButton(
                        onPressed: _signInWithGoogle,
                        icon: Icons.g_mobiledata,
                        label: 'Sign in with Google',
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        iconSize: 32,
                      ),
                      Spacing.verticalXl,
                      // Terms of service
                      Padding(
                        padding: Spacing.horizontalPaddingLg,
                        child: RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white.withOpacity(0.7),
                            ),
                            children: [
                              const TextSpan(text: 'By signing in, you agree to our '),
                              TextSpan(
                                text: 'Terms of Service',
                                style: const TextStyle(
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w600,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const LegalDocumentViewer(
                                          documentType: LegalDocumentType.termsOfService,
                                        ),
                                      ),
                                    );
                                  },
                              ),
                              const TextSpan(text: ' and '),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: const TextStyle(
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w600,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const LegalDocumentViewer(
                                          documentType: LegalDocumentType.privacyPolicy,
                                        ),
                                      ),
                                    );
                                  },
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Test users button (development only)
                      if (kDebugMode) ...[
                        Spacing.verticalXl,
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const TestLoginScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.bug_report),
                          label: const Text('Test Users (Dev Only)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white, width: 2),
                            padding: Spacing.paddingMd,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildAuthButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    double iconSize = 24,
  }) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: foregroundColor, size: iconSize),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: Spacing.borderRadiusMd,
        ),
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.3),
        textStyle: AppTextStyles.button,
      ),
    );
  }
}
