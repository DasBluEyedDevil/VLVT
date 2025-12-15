import 'dart:math';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../constants/spacing.dart';
import '../services/auth_service.dart';
import '../theme/vlvt_colors.dart';
import '../theme/vlvt_text_styles.dart';
import '../utils/error_handler.dart';
import '../widgets/vlvt_button.dart';
import '../widgets/vlvt_input.dart';
import '../widgets/vlvt_loader.dart';
import 'forgot_password_screen.dart';
import 'instagram_email_screen.dart';
import 'legal_document_viewer.dart';
import 'register_screen.dart';
import 'verification_pending_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
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
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => VerificationPendingScreen(
                email: _emailController.text.trim(),
              ),
            ),
          );
        } else {
          // Show error
          final error =
              ErrorHandler.handleError(result['error'] ?? 'Login failed');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.message),
              backgroundColor: VlvtColors.error,
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
                Text(error.message, style: VlvtTextStyles.labelMedium),
                const SizedBox(height: 4),
                Text(error.guidance, style: VlvtTextStyles.caption),
              ],
            ),
            backgroundColor: VlvtColors.error,
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
            backgroundColor: VlvtColors.error,
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
                Text(error.message, style: VlvtTextStyles.labelMedium),
                const SizedBox(height: 4),
                Text(error.guidance, style: VlvtTextStyles.caption),
              ],
            ),
            backgroundColor: VlvtColors.error,
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
            backgroundColor: VlvtColors.error,
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
                Text(error.message, style: VlvtTextStyles.labelMedium),
                const SizedBox(height: 4),
                Text(error.guidance, style: VlvtTextStyles.caption),
              ],
            ),
            backgroundColor: VlvtColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _signInWithInstagram() async {
    // Check if Instagram is configured
    if (!AppConfig.isInstagramConfigured) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Instagram login is not configured'),
            backgroundColor: VlvtColors.warning,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);

    // Get AuthService reference before async gap to avoid BuildContext issues
    final authService = context.read<AuthService>();

    try {
      // Generate cryptographically secure state parameter to prevent CSRF attacks
      final random = Random.secure();
      final stateBytes = List<int>.generate(32, (_) => random.nextInt(256));
      final state = stateBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      // Build Instagram OAuth URL with state parameter
      final authUrl = Uri.https('api.instagram.com', '/oauth/authorize', {
        'client_id': AppConfig.instagramClientId,
        'redirect_uri': AppConfig.instagramRedirectUri,
        'scope': 'user_profile',
        'response_type': 'code',
        'state': state,
      });

      // Launch OAuth flow
      final result = await FlutterWebAuth2.authenticate(
        url: authUrl.toString(),
        callbackUrlScheme: 'vlvt',
      );

      // Extract authorization code and state from callback URL
      final uri = Uri.parse(result);
      final code = uri.queryParameters['code'];
      final returnedState = uri.queryParameters['state'];

      // Verify state parameter to prevent CSRF attacks
      if (returnedState != state) {
        throw Exception('OAuth state mismatch - possible CSRF attack');
      }

      if (code == null) {
        throw Exception('No authorization code received from Instagram');
      }

      // Exchange code for access token via backend
      // Note: The backend handles the token exchange for security
      final response = await authService.signInWithInstagram(code);

      if (mounted) {
        if (response['success'] == true) {
          // Fully authenticated
        } else if (response['needsEmail'] == true) {
          // Instagram user needs to provide email
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => InstagramEmailScreen(
                tempToken: response['tempToken'] ?? '',
                username: response['username'] ?? '',
              ),
            ),
          );
        } else {
          final error = ErrorHandler.handleError(
            response['error'] ?? 'Failed to sign in with Instagram',
          );
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(error.message),
              backgroundColor: VlvtColors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        // User may have cancelled - don't show error for cancellation
        if (!e.toString().contains('CANCELED') &&
            !e.toString().contains('cancelled')) {
          final error = ErrorHandler.handleError(e);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error.message, style: VlvtTextStyles.labelMedium),
                  const SizedBox(height: 4),
                  Text(error.guidance, style: VlvtTextStyles.caption),
                ],
              ),
              backgroundColor: VlvtColors.error,
            ),
          );
        }
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
      extendBodyBehindAppBar: true,
      extendBody: true,
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: Stack(
          fit: StackFit.expand,
          children: [
            // Background image with blur effect
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                child: Image.asset(
                  'assets/images/loginbackground.jpg',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            // Dark overlay for better contrast
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.black.withValues(alpha: 0.7),
                      const Color(0xFF1A0F2E).withValues(alpha: 0.9),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            // Content with SafeArea
            Positioned.fill(
              child: SafeArea(
                bottom: false,
                child: SingleChildScrollView(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo - larger size for better branding
                      Image.asset(
                        'assets/images/logo.png',
                        width: 340,
                        height: 340,
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
                                const VlvtProgressIndicator(
                                  size: 40,
                                  strokeWidth: 3,
                                ),
                                Spacing.verticalMd,
                                Text(
                                  'Signing in...',
                                  style: VlvtTextStyles.bodyMedium.copyWith(
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
                              // Email input - dark glassmorphism style
                              VlvtInput(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                blur: false,
                                hintText: 'Email',
                                prefixIcon: Icons.email_outlined,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Please enter your email';
                                  }
                                  // RFC 5322 compliant email regex
                                  final emailRegex = RegExp(
                                    r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,253}[a-zA-Z0-9])?)*$',
                                  );
                                  if (!emailRegex.hasMatch(value.trim())) {
                                    return 'Please enter a valid email address';
                                  }
                                  return null;
                                },
                              ),
                              Spacing.verticalMd,
                              // Password input - dark glassmorphism style
                              VlvtInput(
                                controller: _passwordController,
                                obscureText: _obscurePassword,
                                autocorrect: false,
                                blur: false,
                                hintText: 'Password',
                                prefixIcon: Icons.lock_outlined,
                                suffixIcon: _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                onSuffixTap: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
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
                              Spacing.verticalLg,
                              // Sign In button with glow effect
                              VlvtButton.primary(
                                label: 'Sign In',
                                onPressed: _signInWithEmail,
                                expanded: true,
                              ),
                              Spacing.verticalMd,
                              // Forgot password - centered under button
                              Center(
                                child: VlvtButton.text(
                                  label: 'Forgot password?',
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const ForgotPasswordScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Spacing.verticalMd,
                              // Create account link
                              Center(
                                child: GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const RegisterScreen(),
                                      ),
                                    );
                                  },
                                  child: RichText(
                                    text: TextSpan(
                                      style: VlvtTextStyles.bodyMedium.copyWith(
                                        color: Colors.white.withValues(alpha: 0.8),
                                      ),
                                      children: [
                                        const TextSpan(text: "Don't have an account? "),
                                        TextSpan(
                                          text: 'Get on the list',
                                          style: TextStyle(
                                            color: const Color(0xFFD4AF37),
                                            fontWeight: FontWeight.w600,
                                            decoration: TextDecoration.underline,
                                            decorationColor: const Color(0xFFD4AF37),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
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
                                color: Colors.white.withValues(alpha: 0.7),
                                thickness: 1,
                              ),
                            ),
                            Padding(
                              padding: Spacing.horizontalPaddingMd,
                              child: Text(
                                'or continue with',
                                style: VlvtTextStyles.bodySmall.copyWith(
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: Colors.white.withValues(alpha: 0.7),
                                thickness: 1,
                              ),
                            ),
                          ],
                        ),
                        Spacing.verticalXl,
                        // OAuth buttons row - following brand guidelines
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Google button - requires white background per guidelines
                            _buildGoogleButton(onPressed: _signInWithGoogle),
                            Spacing.horizontalLg,
                            // Apple button - white logo on dark/transparent
                            _buildOAuthIconButton(
                              onPressed: _signInWithApple,
                              assetPath: 'assets/images/apple_logo_white.png',
                              invertColor: true,
                            ),
                            Spacing.horizontalLg,
                            // Instagram button - white glyph per guidelines
                            _buildOAuthIconButton(
                              onPressed: _signInWithInstagram,
                              assetPath: 'assets/images/instagram_logo.png',
                              invertColor: true,
                            ),
                          ],
                        ),
                        Spacing.verticalXl,
                        // Terms of service - single row
                        Center(
                          child: RichText(
                            text: TextSpan(
                              style: VlvtTextStyles.caption.copyWith(
                                color: Colors.white.withValues(alpha: 0.7),
                              ),
                              children: [
                                const TextSpan(text: 'By signing in, you agree to our '),
                                TextSpan(
                                  text: 'Terms',
                                  style: const TextStyle(
                                    decoration: TextDecoration.underline,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  recognizer: TapGestureRecognizer()
                                    ..onTap = () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const LegalDocumentViewer(
                                            documentType: LegalDocumentType.termsOfService,
                                          ),
                                        ),
                                      );
                                    },
                                ),
                                const TextSpan(text: ' & '),
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
                                          builder: (context) =>
                                              const LegalDocumentViewer(
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
                        Spacing.verticalLg,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }

  // Google button - requires white background with colored G logo per brand guidelines
  Widget _buildGoogleButton({required VoidCallback onPressed}) {
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
          child: Image.asset(
            'assets/images/google_g_logo.png',
            width: 28,
            height: 28,
          ),
        ),
      ),
    );
  }

  Widget _buildOAuthIconButton({
    required VoidCallback onPressed,
    String? assetPath,
    IconData? icon,
    Color? iconColor,
    bool invertColor = false,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.5),
            width: 1.5,
          ),
        ),
        child: Center(
          child: assetPath != null
              ? (invertColor
                  ? ColorFiltered(
                      colorFilter: const ColorFilter.mode(
                        Colors.white,
                        BlendMode.srcIn,
                      ),
                      child: Image.asset(
                        assetPath,
                        width: 24,
                        height: 24,
                      ),
                    )
                  : Image.asset(
                      assetPath,
                      width: 24,
                      height: 24,
                    ))
              : Icon(
                  icon,
                  size: 24,
                  color: iconColor ?? Colors.white,
                ),
        ),
      ),
    );
  }
}
