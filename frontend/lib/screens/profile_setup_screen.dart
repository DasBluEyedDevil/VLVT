import 'package:flutter/material.dart';
import 'profile_edit_screen.dart';

class ProfileSetupScreen extends StatelessWidget {
  const ProfileSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // Prevent back navigation during setup
      child: const ProfileEditScreen(
        isFirstTimeSetup: true,
      ),
    );
  }
}
