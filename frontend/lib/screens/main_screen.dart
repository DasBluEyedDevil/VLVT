import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/subscription_service.dart';
import '../services/auth_service.dart';
import '../services/profile_api_service.dart';
import '../models/profile.dart';
import '../widgets/upgrade_banner.dart';
import '../widgets/vlvt_loader.dart';
import '../widgets/gold_shader_mask.dart';
import '../theme/vlvt_colors.dart';
import 'discovery_screen.dart';
import 'matches_screen.dart';
import 'chats_screen.dart';
import 'profile_screen.dart';
import 'profile_setup_screen.dart';
import 'search_screen.dart';

class MainScreen extends StatefulWidget {
  final int initialTab;

  const MainScreen({super.key, this.initialTab = 0});

  @override
  State<MainScreen> createState() => MainScreenState();
}

class MainScreenState extends State<MainScreen> {
  late int _currentIndex;

  void setTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTab;
    // Defer subscription initialization to avoid calling notifyListeners during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeSubscription();
    });
  }

  Future<void> _initializeSubscription() async {
    final authService = context.read<AuthService>();
    final subscriptionService = context.read<SubscriptionService>();

    if (authService.userId != null) {
      // Pass auth token so subscription service can check backend database
      // (needed for test users whose subscriptions are stored in DB, not RevenueCat)
      subscriptionService.setAuthToken(authService.token);
      await subscriptionService.initialize(authService.userId!);
    }
  }


  @override
  Widget build(BuildContext context) {
    final subscriptionService = context.watch<SubscriptionService>();
    final authService = context.watch<AuthService>();
    final profileService = context.watch<ProfileApiService>();

    // Loading state - use VLVT loader
    if (subscriptionService.isLoading) {
      return Scaffold(
        backgroundColor: VlvtColors.background,
        body: const Center(
          child: VlvtLoader(),
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
        // Loading state - use VLVT loader
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: VlvtColors.background,
            body: const Center(
              child: VlvtLoader(),
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
          // Allow profile creation without ID verification
          // ID verification will be required for messaging instead
          return const ProfileSetupScreen();
        }

        // Profile is complete, show main app
        // Different navigation based on premium status
        final hasPremium = subscriptionService.hasPremiumAccess;

        // Premium users: Discovery, Matches, Profile
        // Free users: Search, Profile
        final List<Widget> screens;
        final List<BottomNavigationBarItem> navItems;

        if (hasPremium) {
          screens = const [
            DiscoveryScreen(),
            MatchesScreen(),
            ChatsScreen(),
            ProfileScreen(),
          ];
          navItems = const [
            BottomNavigationBarItem(
              icon: Icon(Icons.explore),
              label: 'Discovery',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.favorite),
              label: 'Matches',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble),
              label: 'Chats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ];
        } else {
          screens = const [
            SearchScreen(),
            ProfileScreen(),
          ];
          navItems = const [
            BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: 'Search',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person),
              label: 'Profile',
            ),
          ];
        }

        // Ensure current index is valid for current nav items without triggering extra rebuilds
        final safeIndex = _currentIndex.clamp(0, screens.length - 1);
        if (safeIndex != _currentIndex) {
          _currentIndex = safeIndex;
        }

        return Scaffold(
          backgroundColor: VlvtColors.background,
          extendBody: true,
          body: Column(
            children: [
              // Show upgrade banner for free users
              if (!hasPremium) const UpgradeBanner(),
              // Main content
              Expanded(
                child: screens[safeIndex],
              ),
            ],
          ),
          bottomNavigationBar: _buildFrostedNavBar(
            currentIndex: safeIndex,
            items: navItems,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
        );
      },
    );
  }

  /// Builds a frosted glass bottom navigation bar with metallic gold active state
  Widget _buildFrostedNavBar({
    required int currentIndex,
    required List<BottomNavigationBarItem> items,
    required ValueChanged<int> onTap,
  }) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: VlvtColors.surface.withValues(alpha: 0.85),
            border: Border(
              top: BorderSide(
                color: VlvtColors.gold.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(items.length, (index) {
                  final item = items[index];
                  final isSelected = index == currentIndex;

                  return GestureDetector(
                    onTap: () {
                      if (index != currentIndex) {
                        HapticFeedback.selectionClick();
                      }
                      onTap(index);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Icon with metallic gold shader for selected state
                          Container(
                            decoration: isSelected
                                ? BoxDecoration(
                                    boxShadow: [
                                      BoxShadow(
                                        color: VlvtColors.gold.withValues(alpha: 0.4),
                                        blurRadius: 12,
                                        spreadRadius: 0,
                                      ),
                                    ],
                                  )
                                : null,
                            child: isSelected
                                ? GoldShaderMask(
                                    child: IconTheme(
                                      data: const IconThemeData(
                                        color: Colors.white,
                                        size: 24,
                                      ),
                                      child: item.icon,
                                    ),
                                  )
                                : IconTheme(
                                    data: IconThemeData(
                                      color: VlvtColors.textMuted,
                                      size: 24,
                                    ),
                                    child: item.icon,
                                  ),
                          ),
                          const SizedBox(height: 4),
                          // Label with metallic gold for selected state
                          isSelected
                              ? GoldShaderMask(
                                  child: Text(
                                    item.label ?? '',
                                    style: const TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  item.label ?? '',
                                  style: TextStyle(
                                    fontFamily: 'Montserrat',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w400,
                                    color: VlvtColors.textMuted,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
