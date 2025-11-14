import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/subscription_service.dart';
import '../services/auth_service.dart';
import '../services/profile_api_service.dart';
import '../models/profile.dart';
import '../widgets/upgrade_banner.dart';
import 'discovery_screen.dart';
import 'matches_screen.dart';
import 'profile_screen.dart';
import 'profile_setup_screen.dart';

class MainScreen extends StatefulWidget {
  final int initialTab;

  const MainScreen({super.key, this.initialTab = 0});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  late int _currentIndex;

  void setTab(int index) {
    if (index >= 0 && index < 3) {
      setState(() {
        _currentIndex = index;
      });
    }
  }
  
  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
    _initializeSubscription();
  }
  
  Future<void> _initializeSubscription() async {
    final authService = context.read<AuthService>();
    final subscriptionService = context.read<SubscriptionService>();
    
    if (authService.userId != null) {
      await subscriptionService.initialize(authService.userId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionService = context.watch<SubscriptionService>();
    final authService = context.watch<AuthService>();
    final profileService = context.watch<ProfileApiService>();

    // Loading state
    if (subscriptionService.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final userId = authService.userId;
    if (userId == null) {
      return const Scaffold(
        body: Center(
          child: Text('User not authenticated'),
        ),
      );
    }

    // Check if profile setup is needed
    return FutureBuilder<Profile>(
      future: profileService.getProfile(userId),
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // Check if profile needs setup
        // Profile not found (404) or incomplete profile data
        final profile = snapshot.data;
        final hasError = snapshot.hasError;
        final needsSetup = hasError ||
                          profile == null ||
                          profile.name == null ||
                          profile.age == null;

        if (needsSetup) {
          return const ProfileSetupScreen();
        }

        // Profile is complete, show main app
        final screens = [
          const DiscoveryScreen(),
          const MatchesScreen(),
          const ProfileScreen(),
        ];

        return Scaffold(
          body: Column(
            children: [
              // Show upgrade banner if in demo mode
              const UpgradeBanner(),
              // Main content
              Expanded(
                child: screens[_currentIndex],
              ),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.explore),
                label: 'Discovery',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.favorite),
                label: 'Matches',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}
