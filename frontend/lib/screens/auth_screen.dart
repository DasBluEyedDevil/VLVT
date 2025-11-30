import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../constants/spacing.dart';
import '../constants/text_styles.dart';
import '../utils/error_handler.dart';
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
        child: Stack(
          children: [
            // Background image - fills entire screen
            Positioned.fill(
              child: Image.asset(
                'assets/images/loginbackground.jpg',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: const Color(0xFF1A0F2E),
                    child: Center(
                      child: Text('Image failed: $error', style: const TextStyle(color: Colors.white)),
                    ),
                  );
                },
              ),
            ),
            // Content
            SafeArea(
              bottom: false,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: SingleChildScrollView(
                    padding: Spacing.paddingLg,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo
                        Image.asset(
                          'assets/images/logo.png',
                          width: 180,
                          height: 180,
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
                        Spacing.verticalXl,
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
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.5),
                                  hintText: 'Email',
                                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                                  prefixIcon: Icon(Icons.email_outlined, color: Colors.white.withValues(alpha: 0.7)),
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
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: Colors.white.withValues(alpha: 0.5),
                                  hintText: 'Password',
                                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                                  prefixIcon: Icon(Icons.lock_outlined, color: Colors.white.withValues(alpha: 0.7)),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                      color: Colors.white.withValues(alpha: 0.7),
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
                              Center(
                                child: ElevatedButton(
                                  onPressed: _signInWithEmail,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 48),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: Spacing.borderRadiusMd,
                                    ),
                                    elevation: 4,
                                    textStyle: AppTextStyles.button,
                                  ),
                                  child: const Text('Sign In'),
                                ),
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
                        // OAuth buttons row - icon only
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Google button
                            _buildOAuthIconButton(
                              onPressed: _signInWithGoogle,
                              assetPath: 'assets/images/google_logo.png',
                            ),
                            Spacing.horizontalLg,
                            // Apple button
                            _buildOAuthIconButton(
                              onPressed: _signInWithApple,
                              assetPath: 'assets/images/apple_logo.png',
                            ),
                            Spacing.horizontalLg,
                            // Instagram button
                            _buildOAuthIconButton(
                              onPressed: () {
                                // TODO: Implement Instagram OAuth
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Instagram login - coming soon'),
                                  ),
                                );
                              },
                              assetPath: 'assets/images/instagram_logo.png',
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
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
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

  Widget _buildOAuthIconButton({
    required VoidCallback onPressed,
    String? assetPath,
    IconData? icon,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: assetPath != null
              ? Image.asset(
                  assetPath,
                  width: 28,
                  height: 28,
                )
              : Icon(
                  icon,
                  size: 32,
                  color: iconColor ?? Colors.black87,
                ),
        ),
      ),
    );
  }
}
