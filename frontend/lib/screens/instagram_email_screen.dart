import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../constants/spacing.dart';
import '../widgets/vlvt_input.dart';
import '../theme/vlvt_colors.dart';
import '../theme/vlvt_text_styles.dart';
import '../utils/error_handler.dart';
import 'verification_pending_screen.dart';

class InstagramEmailScreen extends StatefulWidget {
  final String tempToken;
  final String username;

  const InstagramEmailScreen({
    super.key,
    required this.tempToken,
    required this.username,
  });

  @override
  State<InstagramEmailScreen> createState() => _InstagramEmailScreenState();
}

class _InstagramEmailScreenState extends State<InstagramEmailScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

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
    super.dispose();
  }

  Future<void> _completeRegistration() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final result = await authService.completeInstagramRegistration(
        widget.tempToken,
        _emailController.text.trim(),
      );

      if (mounted) {
        if (result['success'] == true) {
          // Navigate to VerificationPendingScreen
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => VerificationPendingScreen(
                email: _emailController.text.trim(),
              ),
            ),
          );
        } else {
          // Show error
          final error = ErrorHandler.handleError(result['message'] ?? 'Registration failed');
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

  void _cancel() {
    Navigator.pop(context);
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
                    ? VlvtColors.primaryDark
                    : VlvtColors.primary,
                Theme.of(context).brightness == Brightness.dark
                    ? VlvtColors.primaryDark.withValues(alpha: 0.7)
                    : VlvtColors.primary.withValues(alpha: 0.7),
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
                      // Instagram icon
                      Container(
                        padding: Spacing.paddingXl,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          size: 100,
                          color: Colors.white,
                        ),
                      ),
                      Spacing.verticalXl,
                      // Welcome message
                      Text(
                        'Welcome, @${widget.username}!',
                        textAlign: TextAlign.center,
                        style: VlvtTextStyles.displaySmall.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Spacing.verticalMd,
                      // Explanation text
                      Padding(
                        padding: Spacing.horizontalPaddingXl,
                        child: Text(
                          'Instagram doesn\'t share your email. Please provide one to complete your account.',
                          textAlign: TextAlign.center,
                          style: VlvtTextStyles.bodyMedium.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
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
                                  'Completing registration...',
                                  style: VlvtTextStyles.bodyMedium.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else ...[
                        // Email form
                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Email input
                              VlvtInput(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autocorrect: false,
                                hintText: 'Email',
                                prefixIcon: Icons.email_outlined,
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
                              // Continue button
                              ElevatedButton(
                                onPressed: _completeRegistration,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: VlvtColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                  ),
                                  elevation: 4,
                                  textStyle: VlvtTextStyles.button,
                                ),
                                child: const Text('Continue'),
                              ),
                              Spacing.verticalMd,
                              // Cancel button
                              OutlinedButton(
                                onPressed: _cancel,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(color: Colors.white.withValues(alpha: 0.8), width: 2),
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: Spacing.borderRadiusMd,
                                  ),
                                  textStyle: VlvtTextStyles.button,
                                ),
                                child: const Text('Cancel'),
                              ),
                            ],
                          ),
                        ),
                        Spacing.verticalXl,
                        // Privacy note
                        Padding(
                          padding: Spacing.horizontalPaddingXl,
                          child: Text(
                            'We\'ll send a verification email to this address to complete your account setup.',
                            textAlign: TextAlign.center,
                            style: VlvtTextStyles.caption.copyWith(
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
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
}
