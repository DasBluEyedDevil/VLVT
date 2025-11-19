import 'package:flutter/material.dart';

/// Application Colors with Dark Mode Support
/// Provides theme-aware colors that work in both light and dark modes
class AppColors {
  // Prevent instantiation
  AppColors._();

  // ===== PRIMARY BRAND COLORS =====

  /// Primary brand color (Deep Purple)
  static const Color primaryLight = Color(0xFF673AB7);
  static const Color primaryDark = Color(0xFF9575CD);

  /// Secondary/accent color (Cyan/Teal)
  static const Color secondaryLight = Color(0xFF00BCD4);
  static const Color secondaryDark = Color(0xFF80DEEA);

  // ===== MESSAGE BUBBLE COLORS =====

  /// Message bubble background for sent messages (current user)
  static Color messageBubbleSent(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? primaryDark
        : primaryLight;
  }

  /// Message bubble background for received messages (other user)
  static Color messageBubbleReceived(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceVariant
        : Colors.grey[200]!;
  }

  /// Text color for sent message bubbles
  static Color messageBubbleTextSent(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.white; // Always white on primary color
  }

  /// Text color for received message bubbles
  static Color messageBubbleTextReceived(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  /// Timestamp text color for sent messages
  static Color messageTimestampSent(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withOpacity(0.7)
        : Colors.white.withOpacity(0.7);
  }

  /// Timestamp text color for received messages
  static Color messageTimestampReceived(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6);
  }

  // ===== STATUS & INDICATOR COLORS =====

  /// Success/positive state (green)
  static Color success(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.green.shade400
        : Colors.green.shade600;
  }

  /// Error/negative state (red)
  static Color error(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.red.shade400
        : Colors.red.shade600;
  }

  /// Warning state (orange)
  static Color warning(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.orange.shade400
        : Colors.orange.shade600;
  }

  /// Info state (blue)
  static Color info(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.blue.shade400
        : Colors.blue.shade600;
  }

  // ===== TEXT COLORS =====

  /// Primary text color (adapts to theme)
  static Color textPrimary(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface;
  }

  /// Secondary/muted text color
  static Color textSecondary(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant;
  }

  /// Disabled/hint text color
  static Color textDisabled(BuildContext context) {
    return Theme.of(context).colorScheme.onSurface.withOpacity(0.38);
  }

  // ===== BACKGROUND COLORS =====

  /// Card/surface background
  static Color surface(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }

  /// Elevated surface (slightly lighter/darker than surface)
  static Color surfaceElevated(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surface.withOpacity(0.95)
        : Colors.white;
  }

  /// Input field background
  static Color inputBackground(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Theme.of(context).colorScheme.surfaceVariant
        : Colors.grey[200]!;
  }

  // ===== BORDER COLORS =====

  /// Default border color
  static Color border(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white.withOpacity(0.12)
        : Colors.black.withOpacity(0.12);
  }

  /// Divider color
  static Color divider(BuildContext context) {
    return Theme.of(context).dividerColor;
  }

  // ===== TYPING INDICATOR =====

  /// Typing indicator bubble background
  static Color typingIndicatorBackground(BuildContext context) {
    return messageBubbleReceived(context);
  }

  /// Typing indicator dots color
  static Color typingIndicatorDots(BuildContext context) {
    return Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6);
  }

  // ===== SUBSCRIPTION/PREMIUM =====

  /// Premium/subscription UI elements
  static Color premium(BuildContext context) {
    return const Color(0xFFFFD700); // Gold color
  }

  /// Free tier UI elements
  static Color freeTier(BuildContext context) {
    return Theme.of(context).colorScheme.secondary;
  }
}
