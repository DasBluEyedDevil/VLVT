import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../constants/spacing.dart';
import '../constants/text_styles.dart';
import '../utils/error_handler.dart';
import 'verification_pending_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _validatePassword(String password) {
    // Must be at least 8 characters
    if (password.length < 8) return false;

    // Must contain at least one letter
    if (!password.contains(RegExp(r'[a-zA-Z]'))) return false;

    // Must contain at least one number
    if (!password.contains(RegExp(r'[0-9]'))) return false;

    return true;
  }

  String _getPasswordRequirements(String password) {
    final requirements = <String>[];

    if (password.length < 8) {
      requirements.add('At least 8 characters');
    }
    if (!password.contains(RegExp(r'[a-zA-Z]'))) {
      requirements.add('At least one letter');
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      requirements.add('At least one number');
    }

    if (requirements.isEmpty) {
      return 'Password meets all requirements';
    }

    return 'Required: ${requirements.join(', ')}';
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = context.read<AuthService>();
      final result = await authService.registerWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
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
          final error = ErrorHandler.handleError(result['error'] ?? 'Registration failed');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error.message, style: AppTextStyles.labelMedium),
                  if (result['details'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      result['details'].toString(),
                      style: AppTextStyles.caption,
                    ),
                  ],
                ],
              ),
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
            child: Padding(
              padding: Spacing.paddingLg,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Back button
                  Align(
                    alignment: Alignment.topLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
                  // Title
                  Text(
                    'Create Account',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.displaySmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacing.verticalMd,
                  Text(
                    'Join VLVT and start making meaningful connections',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
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
                              'Creating your account...',
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
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
                            onChanged: (value) {
                              // Trigger rebuild to update password requirements display
                              setState(() {});
                            },
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
                                return 'Please enter a password';
                              }
                              if (!_validatePassword(value)) {
                                return 'Password does not meet requirements';
                              }
                              return null;
                            },
                          ),
                          // Password requirements display
                          if (_passwordController.text.isNotEmpty) ...[
                            Spacing.verticalSm,
                            Container(
                              padding: Spacing.paddingMd,
                              decoration: BoxDecoration(
                                color: _validatePassword(_passwordController.text)
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : Colors.white.withValues(alpha: 0.15),
                                borderRadius: Spacing.borderRadiusMd,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _validatePassword(_passwordController.text)
                                        ? Icons.check_circle
                                        : Icons.info_outline,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _getPasswordRequirements(_passwordController.text),
                                      style: AppTextStyles.caption.copyWith(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          Spacing.verticalMd,
                          // Confirm password input
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: _obscureConfirmPassword,
                            autocorrect: false,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: Colors.white,
                              hintText: 'Confirm Password',
                              prefixIcon: const Icon(Icons.lock_outlined),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword = !_obscureConfirmPassword;
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
                                return 'Please confirm your password';
                              }
                              if (value != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          Spacing.verticalXl,
                          // Register button
                          ElevatedButton(
                            onPressed: _register,
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
                            child: const Text('Create Account'),
                          ),
                          Spacing.verticalMd,
                          // Sign in link
                          Center(
                            child: TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(
                                'Already have an account? Sign in',
                                style: AppTextStyles.bodySmall.copyWith(
                                  color: Colors.white,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
