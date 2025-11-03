import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/subscription_service.dart';
import '../services/auth_service.dart';
import 'discovery_screen.dart';
import 'matches_screen.dart';
import 'profile_screen.dart';
import 'paywall_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  
  @override
  void initState() {
    super.initState();
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
    
    // If no premium access, show paywall
    if (!subscriptionService.hasPremiumAccess && !subscriptionService.isLoading) {
      return const PaywallScreen();
    }
    
    // Loading state
    if (subscriptionService.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    final screens = [
      const DiscoveryScreen(),
      const MatchesScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: screens[_currentIndex],
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
  }
}
