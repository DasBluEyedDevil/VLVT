import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/theme_service.dart';
import 'vlvt_button.dart';
import 'vlvt_card.dart';

/// Widget for toggling between light and dark themes
class ThemeToggleWidget extends StatelessWidget {
  const ThemeToggleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();

    return VlvtSurfaceCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          themeService.isDarkMode ? Icons.dark_mode : Icons.light_mode,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: const Text(
          'Dark Mode',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(_getThemeModeText(themeService.themeMode)),
        trailing: Switch(
          value: themeService.themeMode == ThemeMode.dark,
          onChanged: (value) {
            themeService.setThemeMode(
              value ? ThemeMode.dark : ThemeMode.light,
            );
          },
        ),
        onTap: () {
          // Show theme options dialog
          _showThemeDialog(context, themeService);
        },
      ),
    );
  }

  String _getThemeModeText(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light theme enabled';
      case ThemeMode.dark:
        return 'Dark theme enabled';
      case ThemeMode.system:
        return 'Following system preference';
    }
  }

  void _showThemeDialog(BuildContext context, ThemeService themeService) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Theme Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Light'),
              subtitle: const Text('Always use light theme'),
              leading: Radio<ThemeMode>(
                value: ThemeMode.light,
                groupValue: themeService.themeMode,
                onChanged: (value) {
                  if (value != null) {
                    themeService.setThemeMode(value);
                    Navigator.of(context).pop();
                  }
                },
              ),
              onTap: () {
                themeService.setThemeMode(ThemeMode.light);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('Dark'),
              subtitle: const Text('Always use dark theme'),
              leading: Radio<ThemeMode>(
                value: ThemeMode.dark,
                groupValue: themeService.themeMode,
                onChanged: (value) {
                  if (value != null) {
                    themeService.setThemeMode(value);
                    Navigator.of(context).pop();
                  }
                },
              ),
              onTap: () {
                themeService.setThemeMode(ThemeMode.dark);
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              title: const Text('System'),
              subtitle: const Text('Follow system theme'),
              leading: Radio<ThemeMode>(
                value: ThemeMode.system,
                groupValue: themeService.themeMode,
                onChanged: (value) {
                  if (value != null) {
                    themeService.setThemeMode(value);
                    Navigator.of(context).pop();
                  }
                },
              ),
              onTap: () {
                themeService.setThemeMode(ThemeMode.system);
                Navigator.of(context).pop();
              },
            ),
          ],
        ),
        actions: [
          VlvtButton.text(
            label: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
