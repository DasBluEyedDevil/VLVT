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
import 'register_screen.dart';
import 'forgot_password_screen.dart';

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

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final result = await authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (mounted) {
        if (result['success'] == true) {
          // Success - navigation handled by AuthService
        } else if (result['code'] == 'EMAIL_NOT_VERIFIED') {
          // Navigate to VerificationPendingScreen
          // TODO: Implement VerificationPendingScreen
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please verify your email address'),
              backgroundColor: AppColors.warning(context),
            ),
          );
        } else {
          // Show error
          final error = ErrorHandler.handleError(result['error'] ?? 'Login failed');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.message),
              backgroundColor: AppColors.error(context),
            ),
          );
        }
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
            backgroundColor: AppColors.error(context),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
            backgroundColor: AppColors.error(context),
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
            backgroundColor: AppColors.error(context),
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
            backgroundColor: AppColors.error(context),
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
            backgroundColor: AppColors.error(context),
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
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Theme.of(context).brightness == Brightness.dark
                    ? AppColors.primaryDark
                    : AppColors.primaryLight,
                Theme.of(context).brightness == Brightness.dark
                    ? AppColors.primaryDark.withValues(alpha: 0.7)
                    : AppColors.primaryLight.withValues(alpha: 0.7),
              ],
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
                          color: Colors.white.withValues(alpha: 0.15),
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
                        'VLVT',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.displaySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacing.verticalMd,
                      Text(
                        'See what\'s waiting behind the rope.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.h4.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
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
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      Spacing.verticalXxl,
                      // Loading indicator or form
                      if (_isLoading)
                        Center(
                          child: Container(
                            padding: Spacing.paddingXl,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
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
                        // Email/Password Login Form
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Email input
                              TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  hintText: 'Email',
                                  prefixIcon: const Icon(Icons.email_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                    borderSide: const BorderSide(color: Colors.red, width: 2),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                    borderSide: const BorderSide(color: Colors.red, width: 2),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your email';
                                  }
                                  if (!value.contains('@') || !value.contains('.')) {
                                    return 'Please enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                              Spacing.verticalMd,
                              // Password input
                              TextFormField(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autocorrect: false,
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white,
                                  hintText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outlined),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _obscurePassword = !_obscurePassword;
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                    borderSide: const BorderSide(color: AppColors.primary, width: 2),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                    borderSide: const BorderSide(color: Colors.red, width: 2),
                                  ),
                                  focusedErrorBorder: OutlineInputBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                    borderSide: const BorderSide(color: Colors.red, width: 2),
                                  ),
                                ),
                                validator: (value) {
                                  if (value == null || value.isEmpty) {
                                    return 'Please enter your password';
                                  }
                                  if (value.length < 6) {
                                    return 'Password must be at least 6 characters';
                                  }
                                  return null;
                                },
                              ),
                              Spacing.verticalMd,
                              // Sign In button
                              ElevatedButton(
                                onPressed: _signInWithEmail,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                  ),
                                  elevation: 4,
                                  textStyle: AppTextStyles.button,
                                ),
                                child: const Text('Sign In'),
                              ),
                              Spacing.verticalMd,
                              // Forgot password and Create account links
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const ForgotPasswordScreen(),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      'Forgot password?',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: Colors.white,
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const RegisterScreen(),
                                        ),
                                      );
                                    },
                                    child: Text(
                                      'Create account',
                                      style: AppTextStyles.bodySmall.copyWith(
                                        color: Colors.white,
                                        decoration: TextDecoration.underline,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Spacing.verticalXl,
                        // Divider
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: Colors.white.withValues(alpha: 0.5),
                                thickness: 1,
                              ),
                            ),
                            Padding(
                              padding: Spacing.horizontalPaddingMd,
                              child: Text(
                                'or continue with',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: Colors.white.withValues(alpha: 0.5),
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),
                        Spacing.verticalXl,
                        // OAuth buttons row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Google button
                            Expanded(
                              child: _buildOAuthButton(
                                onPressed: _signInWithGoogle,
                                icon: Icons.g_mobiledata,
                                label: 'Google',
                                iconSize: 32,
                              ),
                            ),
                            Spacing.horizontalMd,
                            // Apple button (iOS only)
                            if (Platform.isIOS) ...[
                              Expanded(
                                child: _buildOAuthButton(
                                  onPressed: _signInWithApple,
                                  icon: Icons.apple,
                                  label: 'Apple',
                                ),
                              ),
                              Spacing.horizontalMd,
                            ],
                            // Instagram button
                            Expanded(
                              child: _buildOAuthButton(
                                onPressed: () {
                                  // TODO: Implement Instagram OAuth
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Instagram login - coming soon'),
                                    ),
                                  );
                                },
                                icon: Icons.camera_alt,
                                label: 'Instagram',
                              ),
                            ),
                          ],
                        ),
                        Spacing.verticalXl,
                        // Terms of service
                        Padding(
                          padding: Spacing.horizontalPaddingLg,
                          child: RichText(
                            textAlign: TextAlign.center,
                            text: TextSpan(
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.white.withValues(alpha: 0.7),
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
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.8), width: 2),
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
        shadowColor: Colors.black.withValues(alpha: 0.3),
        textStyle: AppTextStyles.button,
      ),
    );
  }

  Widget _buildOAuthButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    double iconSize = 24,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: Spacing.borderRadiusMd,
        ),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize, color: Colors.black87),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: Colors.black87,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
