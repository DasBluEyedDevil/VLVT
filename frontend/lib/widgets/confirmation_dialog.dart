import 'package:flutter/material.dart';
import '../constants/spacing.dart';
import '../constants/text_styles.dart';

/// Reusable confirmation dialog for destructive or important actions
class ConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String? consequences;
  final String confirmText;
  final String cancelText;
  final bool isDestructive;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final IconData? icon;

  const ConfirmationDialog({
    super.key,
    required this.title,
    required this.message,
    this.consequences,
    this.confirmText = 'Confirm',
    this.cancelText = 'Cancel',
    this.isDestructive = false,
    this.onConfirm,
    this.onCancel,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final destructiveColor = AppColors.error(context);
    final warningColor = AppColors.warning(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: Spacing.borderRadiusLg,
      ),
      title: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              color: isDestructive ? destructiveColor : AppColors.primary,
              size: 28,
            ),
            Spacing.horizontalMd,
          ],
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.h3,
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: AppTextStyles.bodyMedium,
          ),
          if (consequences != null) ...[
            Spacing.verticalMd,
            Container(
              padding: Spacing.paddingMd,
              decoration: BoxDecoration(
                color: isDestructive
                    ? destructiveColor.withValues(alpha: 26 / 255)
                    : warningColor.withValues(alpha: 26 / 255),
                borderRadius: Spacing.borderRadiusSm,
                border: Border.all(
                  color: isDestructive
                      ? destructiveColor.withValues(alpha: 77 / 255)
                      : warningColor.withValues(alpha: 77 / 255),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: isDestructive ? destructiveColor : warningColor,
                  ),
                  Spacing.horizontalSm,
                  Expanded(
                    child: Text(
                      consequences!,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isDestructive
                            ? destructiveColor
                            : warningColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Cancel button (secondary)
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(false);
            onCancel?.call();
          },
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          ),
          child: Text(
            cancelText,
            style: AppTextStyles.labelLarge.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Spacing.horizontalSm,
        // Confirm button (primary)
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop(true);
            onConfirm?.call();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isDestructive ? destructiveColor : AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: Spacing.borderRadiusSm,
            ),
          ),
          child: Text(
            confirmText,
            style: AppTextStyles.labelLarge.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }

  /// Show a destructive confirmation dialog (e.g., delete, logout)
  static Future<bool?> showDestructive({
    required BuildContext context,
    required String title,
    required String message,
    String? consequences,
    String confirmText = 'Delete',
    String cancelText = 'Cancel',
    IconData? icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: title,
        message: message,
        consequences: consequences,
        confirmText: confirmText,
        cancelText: cancelText,
        isDestructive: true,
        icon: icon ?? Icons.warning_amber_rounded,
      ),
    );
  }

  /// Show a standard confirmation dialog
  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String message,
    String? consequences,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    IconData? icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => ConfirmationDialog(
        title: title,
        message: message,
        consequences: consequences,
        confirmText: confirmText,
        cancelText: cancelText,
        isDestructive: false,
        icon: icon,
      ),
    );
  }
}

/// Quick access methods for common confirmation dialogs
extension ConfirmationDialogExtensions on BuildContext {
  /// Show logout confirmation
  Future<bool?> confirmLogout() {
    return ConfirmationDialog.showDestructive(
      context: this,
      title: 'Logout',
      message: 'Are you sure you want to logout?',
      consequences: 'You will need to sign in again to access your account.',
      confirmText: 'Logout',
      icon: Icons.logout,
    );
  }

  /// Show unmatch confirmation
  Future<bool?> confirmUnmatch(String name) {
    return ConfirmationDialog.showDestructive(
      context: this,
      title: 'Unmatch',
      message: 'Are you sure you want to unmatch with $name?',
      consequences:
          'This will remove your chat history and you won\'t be able to message each other anymore.',
      confirmText: 'Unmatch',
      icon: Icons.heart_broken,
    );
  }

  /// Show delete message confirmation
  Future<bool?> confirmDeleteMessage() {
    return ConfirmationDialog.showDestructive(
      context: this,
      title: 'Delete Message',
      message: 'Are you sure you want to delete this message?',
      consequences: 'This action cannot be undone.',
      confirmText: 'Delete',
      icon: Icons.delete_outline,
    );
  }

  /// Show delete account confirmation
  Future<bool?> confirmDeleteAccount() {
    return ConfirmationDialog.showDestructive(
      context: this,
      title: 'Delete Account',
      message: 'Are you sure you want to delete your account?',
      consequences:
          'This will permanently delete your account, profile, matches, and all data. This action cannot be undone.',
      confirmText: 'Delete Account',
      icon: Icons.delete_forever,
    );
  }

  /// Show generic confirmation
  Future<bool?> confirm({
    required String title,
    required String message,
    String? consequences,
    String confirmText = 'Confirm',
    bool isDestructive = false,
    IconData? icon,
  }) {
    return isDestructive
        ? ConfirmationDialog.showDestructive(
            context: this,
            title: title,
            message: message,
            consequences: consequences,
            confirmText: confirmText,
            icon: icon,
          )
        : ConfirmationDialog.show(
            context: this,
            title: title,
            message: message,
            consequences: consequences,
            confirmText: confirmText,
            icon: icon,
          );
  }
}
