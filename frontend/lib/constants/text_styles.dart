import 'package:flutter/material.dart';

/// Consistent text styles for the app
class AppTextStyles {
  // Display styles (large headings)
  static const TextStyle displayLarge = TextStyle(
    fontSize: 48,
    fontWeight: FontWeight.bold,
    height: 1.2,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.bold,
    height: 1.2,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.bold,
    height: 1.2,
  );

  // Heading styles
  static const TextStyle h1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    height: 1.3,
  );

  static const TextStyle h2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    height: 1.3,
  );

  static const TextStyle h3 = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.bold,
    height: 1.4,
  );

  static const TextStyle h4 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  // Body styles
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    height: 1.5,
  );

  // Label styles (for buttons, chips, etc.)
  static const TextStyle labelLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  // Caption styles (for small text, timestamps, etc.)
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    height: 1.4,
  );

  static const TextStyle overline = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    height: 1.4,
  );

  // Special styles
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static const TextStyle link = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.underline,
  );

  // Color variants for light backgrounds
  static TextStyle primaryText(Color color) => TextStyle(
        color: color,
        fontSize: 16,
        fontWeight: FontWeight.normal,
      );

  static TextStyle secondaryText(Color color) => TextStyle(
        color: color.withAlpha(179),
        fontSize: 14,
        fontWeight: FontWeight.normal,
      );

  static TextStyle hintText(Color color) => TextStyle(
        color: color.withAlpha(128),
        fontSize: 14,
        fontWeight: FontWeight.normal,
      );

  // Error text
  static const TextStyle error = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: Colors.red,
    height: 1.4,
  );

  // Success text
  static const TextStyle success = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: Colors.green,
    height: 1.4,
  );

  // Warning text
  static const TextStyle warning = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: Colors.orange,
    height: 1.4,
  );
}

/// Color constants for the app
class AppColors {
  // Primary colors
  static const Color primary = Colors.deepPurple;
  static const Color primaryLight = Color(0xFF9575CD);
  static const Color primaryDark = Color(0xFF512DA8);

  // Accent colors
  static const Color accent = Color(0xFFE91E63);

  // Semantic colors
  static Color success(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.green.shade200
          : Colors.green.shade700;
  static Color error(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.red.shade200
          : Colors.red.shade700;
  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.orange.shade200
          : Colors.orange.shade700;
  static Color info(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.blue.shade200
          : Colors.blue.shade700;

  // Neutral colors
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Colors.white;
  static const Color divider = Color(0xFFE0E0E0);

  // Text colors
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFFBDBDBD);
  static const Color textOnPrimary = Colors.white;

  // Action colors (for like/dislike buttons)
  static const Color like = Colors.green;
  static const Color dislike = Colors.red;
  static const Color superLike = Colors.blue;

  // Gradient colors
  static const List<Color> primaryGradient = [
    Color(0xFF9575CD),
    Color(0xFF7E57C2),
    Color(0xFF673AB7),
  ];

  static const List<Color> accentGradient = [
    Color(0xFFFF4081),
    Color(0xFFE91E63),
    Color(0xFFC2185B),
  ];
}
