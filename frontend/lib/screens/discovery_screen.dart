import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/profile_api_service.dart';
import '../services/auth_service.dart';
import '../services/chat_api_service.dart';
import '../services/subscription_service.dart';
import '../services/discovery_preferences_service.dart';
import '../services/analytics_service.dart';
import '../services/location_service.dart';
import '../widgets/premium_gate_dialog.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/swipe_tutorial_overlay.dart';
import '../widgets/match_overlay.dart';
import '../widgets/vlvt_loader.dart';
import '../widgets/vlvt_button.dart';
import '../models/profile.dart';
import '../models/match.dart';
import '../theme/vlvt_colors.dart';
import '../theme/vlvt_text_styles.dart';
import 'discovery_filters_screen.dart';
import 'dart:async';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> with TickerProviderStateMixin {
  int _currentProfileIndex = 0;
  List<Profile> _filteredProfiles = [];
  List<Match>? _currentMatches;
  bool _isLoading = true;
  String? _errorMessage;

  // Undo functionality
  Profile? _lastProfile;
  String? _lastAction; // 'pass' or 'like'
  Match? _lastMatch;
  Timer? _undoTimer;
  bool _showUndoButton = false;

  // Animation
  late AnimationController _cardAnimationController;
  late Animation<double> _cardAnimation;
  bool _isExpanded = false;

  // Photo carousel
  PageController? _photoPageController;
  int _currentPhotoIndex = 0;

  // Swipe gesture state
  Offset _cardPosition = Offset.zero;
  double _cardRotation = 0.0;
  bool _isDragging = false;
  late AnimationController _swipeAnimationController;
  late Animation<Offset> _swipeAnimation;

  // Tutorial state
  bool _showTutorial = false;

  // Micro-interaction state
  bool _showHeartParticles = false;
  String? _matchOverlayUserName;
  bool? _matchOverlayIsNewMatch;
  bool _isShaking = false;

  @override
  void initState() {
    super.initState();
    _cardAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _cardAnimation = CurvedAnimation(
      parent: _cardAnimationController,
      curve: Curves.easeInOut,
    );

    // Initialize swipe animation controller
    _swipeAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _initializeDiscovery();
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    _cardAnimationController.dispose();
    _swipeAnimationController.dispose();
    _photoPageController?.dispose();
    super.dispose();
  }

  Future<void> _initializeDiscovery() async {
    final prefsService = context.read<DiscoveryPreferencesService>();
    await prefsService.init();

    // Restore saved index if available
    final savedIndex = prefsService.getSavedIndex();
    if (savedIndex != null) {
      _currentProfileIndex = savedIndex;
    }

    await _loadProfiles();

    // Show tutorial if first time
    if (!prefsService.hasSeenTutorial && mounted) {
      // Delay to allow screen to settle
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _showTutorial = true;
          });
        }
      });
    }
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profileService = context.read<ProfileApiService>();
      final chatService = context.read<ChatApiService>();
      final authService = context.read<AuthService>();
      final prefsService = context.read<DiscoveryPreferencesService>();
      final currentUserId = authService.userId;

      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      // Get filters
      final filters = prefsService.filters;

      // Get seen profile IDs to exclude
      final seenProfileIds = prefsService.seenProfileIds;

      // Get current matches to exclude
      _currentMatches = await chatService.getMatches(currentUserId);
      final matchedUserIds = _currentMatches!
          .map((m) => m.userId1 == currentUserId ? m.userId2 : m.userId1)
          .toList();

      // Combine exclusions
      final excludeIds = {...seenProfileIds, ...matchedUserIds, currentUserId}.toList();

      // Fetch profiles with filters
      final profiles = await profileService.getDiscoveryProfiles(
        minAge: filters.minAge != 18 ? filters.minAge : null,
        maxAge: filters.maxAge != 99 ? filters.maxAge : null,
        maxDistance: filters.maxDistance != 50.0 ? filters.maxDistance : null,
        interests: filters.selectedInterests.isNotEmpty ? filters.selectedInterests : null,
        excludeUserIds: excludeIds.isNotEmpty ? excludeIds : null,
      );

      setState(() {
        _filteredProfiles = _filterProfilesClientSide(profiles);
        _isLoading = false;

        // Reset index if we have new profiles and current index is invalid
        if (_currentProfileIndex >= _filteredProfiles.length) {
          _currentProfileIndex = 0;
        }
      });

      // Pre-cache upcoming profile images for smoother swiping
      _precacheNextProfiles();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load profiles: $e';
        _isLoading = false;
      });
    }
  }

  List<Profile> _filterProfilesClientSide(List<Profile> profiles) {
    final prefsService = context.read<DiscoveryPreferencesService>();
    final authService = context.read<AuthService>();
    final currentUserId = authService.userId;

    final seenIds = prefsService.seenProfileIds;
    final matchedUserIds = _currentMatches
        ?.map((m) => m.userId1 == currentUserId ? m.userId2 : m.userId1)
        .toSet() ?? {};

    // Filter out seen profiles and matched profiles
    return profiles.where((profile) {
      return profile.userId != currentUserId &&
             !seenIds.contains(profile.userId) &&
             !matchedUserIds.contains(profile.userId);
    }).toList();
  }

  Future<void> _onLike() async {
    if (_filteredProfiles.isEmpty || _currentProfileIndex >= _filteredProfiles.length) {
      return;
    }

    // Check subscription limits
    final subscriptionService = context.read<SubscriptionService>();
    if (!subscriptionService.canLike()) {
      if (mounted) {
        PremiumGateDialog.showLikesLimitReached(context);
      }
      return;
    }

    final profile = _filteredProfiles[_currentProfileIndex];

    // Store for undo
    _lastProfile = profile;
    _lastAction = 'like';

    try {
      // Get services
      final authService = context.read<AuthService>();
      final chatService = context.read<ChatApiService>();
      final prefsService = context.read<DiscoveryPreferencesService>();
      final currentUserId = authService.userId;

      if (currentUserId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not authenticated')),
          );
        }
        return;
      }

      // Use a like (increments counter for demo users)
      await subscriptionService.useLike();

      // Record the action
      await prefsService.recordProfileAction(profile.userId, 'like');

      // Track profile liked event
      await AnalyticsService.logProfileLiked(profile.userId);

      // Create match
      final result = await chatService.createMatch(currentUserId, profile.userId);
      final alreadyExists = result['alreadyExists'] as bool;
      _lastMatch = result['match'] as Match?;

      // Track match creation if new match
      if (!alreadyExists && _lastMatch != null) {
        await AnalyticsService.logMatchCreated(_lastMatch!.matchId);
      }

      if (mounted) {
        // Heavy haptic feedback for actual match (not already existing)
        if (!alreadyExists) {
          HapticFeedback.heavyImpact();
        }

        // Show heart particles animation
        setState(() {
          _showHeartParticles = true;
        });

        // Show match overlay instead of Snackbar
        setState(() {
          _matchOverlayUserName = profile.name ?? "user";
          _matchOverlayIsNewMatch = !alreadyExists;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create match: $e')),
        );
      }
    }

    // Move to next profile and show undo button
    _moveToNextProfile();
    _showUndo();
  }

  Future<void> _onPass() async {
    if (_filteredProfiles.isEmpty || _currentProfileIndex >= _filteredProfiles.length) {
      return;
    }

    final profile = _filteredProfiles[_currentProfileIndex];

    // Store for undo
    _lastProfile = profile;
    _lastAction = 'pass';

    // Record the action
    final prefsService = context.read<DiscoveryPreferencesService>();
    await prefsService.recordProfileAction(profile.userId, 'pass');

    // Track profile passed event
    await AnalyticsService.logProfilePassed(profile.userId);

    // Trigger subtle shake animation
    _triggerShakeAnimation();

    // Move to next profile and show undo button
    _moveToNextProfile();
    _showUndo();
  }

  void _triggerShakeAnimation() {
    if (_isShaking) return;

    // Use addPostFrameCallback to avoid animation conflicts during layout
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isShaking = true;
      });

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isShaking = false;
          });
        }
      });
    });
  }

  void _moveToNextProfile() {
    // Dispose controller outside of setState to avoid animation conflicts
    final oldController = _photoPageController;
    _photoPageController = null;

    setState(() {
      if (_currentProfileIndex < _filteredProfiles.length - 1) {
        _currentProfileIndex++;
        _currentPhotoIndex = 0;
        _saveCurrentIndex();
        // Pre-cache upcoming profile images
        _precacheNextProfiles();
      } else {
        _showEndOfProfilesMessage();
      }
    });

    // Dispose after setState completes
    oldController?.dispose();
  }

  void _initPhotoController(int photoCount) {
    if (_photoPageController == null && photoCount > 0) {
      _photoPageController = PageController(initialPage: 0);
    }
  }

  /// Pre-cache images for upcoming profiles to eliminate loading spinners
  void _precacheNextProfiles() {
    if (_filteredProfiles.isEmpty) return;

    final profileService = context.read<ProfileApiService>();

    // Pre-cache next 2 profiles
    for (int i = 1; i <= 2; i++) {
      final nextIndex = _currentProfileIndex + i;
      if (nextIndex < _filteredProfiles.length) {
        final photos = _filteredProfiles[nextIndex].photos;
        if (photos != null && photos.isNotEmpty) {
          for (final photoUrl in photos.take(2)) {
            // Pre-fetch first 2 photos of each upcoming profile
            final url = photoUrl.startsWith('http')
                ? photoUrl
                : '${profileService.baseUrl}$photoUrl';
            // Use CachedNetworkImageProvider to trigger cache
            CachedNetworkImageProvider(url).resolve(ImageConfiguration.empty);
          }
        }
      }
    }
  }

  /// Calculate parallax alignment based on card drag position
  Alignment _getParallaxAlignment() {
    // Invert drag direction for depth effect
    // Card moving right -> image shifts left (reveals more right side)
    final parallaxX = (_cardPosition.dx / 300).clamp(-1.0, 1.0) * -0.3;
    return Alignment(parallaxX, 0.0);
  }

  void _showUndo() {
    setState(() {
      _showUndoButton = true;
    });

    _undoTimer?.cancel();
    _undoTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showUndoButton = false;
          _lastProfile = null;
          _lastAction = null;
          _lastMatch = null;
        });
      }
    });
  }

  // Swipe gesture handlers
  void _onPanStart(DragStartDetails details) {
    // Block swiping for non-premium users
    final subscriptionService = context.read<SubscriptionService>();
    if (!subscriptionService.hasPremiumAccess) {
      HapticFeedback.heavyImpact();
      PremiumGateDialog.showSwipingRequired(context);
      return;
    }

    HapticFeedback.selectionClick();
    setState(() {
      _isDragging = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    // Ignore if not dragging (blocked for non-premium)
    if (!_isDragging) return;

    setState(() {
      _cardPosition += details.delta;

      // Calculate rotation based on horizontal position (max 20 degrees)
      _cardRotation = (_cardPosition.dx / 1000).clamp(-0.35, 0.35);
    });
  }

  void _onPanEnd(DragEndDetails details) {
    // Ignore if not dragging (blocked for non-premium)
    if (!_isDragging) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final threshold = screenWidth * 0.3; // 30% of screen width

    setState(() {
      _isDragging = false;
    });

    // Check if swiped far enough
    if (_cardPosition.dx.abs() > threshold) {
      // Determine swipe direction
      final swipeRight = _cardPosition.dx > 0;

      // Animate card off screen
      final targetX = swipeRight ? screenWidth * 1.5 : -screenWidth * 1.5;
      _swipeAnimation = Tween<Offset>(
        begin: _cardPosition,
        end: Offset(targetX, _cardPosition.dy),
      ).animate(CurvedAnimation(
        parent: _swipeAnimationController,
        curve: Curves.easeOut,
      ));

      _swipeAnimationController.forward(from: 0).then((_) {
        // Defer state changes to next frame to avoid layout conflicts
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Reset card position
          setState(() {
            _cardPosition = Offset.zero;
            _cardRotation = 0.0;
          });
          _swipeAnimationController.reset();

          // Trigger appropriate action with haptic feedback
          if (swipeRight) {
            HapticFeedback.mediumImpact();
            _onLike();
          } else {
            HapticFeedback.lightImpact();
            _onPass();
          }
        });
      });
    } else {
      // Snap back to center
      _swipeAnimation = Tween<Offset>(
        begin: _cardPosition,
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _swipeAnimationController,
        curve: Curves.elasticOut,
      ));

      _swipeAnimationController.forward(from: 0).then((_) {
        // Defer state changes to next frame to avoid layout conflicts
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _cardPosition = Offset.zero;
            _cardRotation = 0.0;
          });
          _swipeAnimationController.reset();
        });
      });
    }
  }

  Future<void> _onUndo() async {
    if (_lastProfile == null || _lastAction == null) {
      debugPrint('Undo: No last profile or action to undo');
      return;
    }
    if (!mounted) {
      debugPrint('Undo: Widget not mounted');
      return;
    }

    debugPrint('Undo: Starting undo for ${_lastProfile?.userId}');
    debugPrint('Undo: Current index: $_currentProfileIndex, profiles count: ${_filteredProfiles.length}');

    _undoTimer?.cancel();

    try {
      final prefsService = context.read<DiscoveryPreferencesService>();

      // Track undo event (don't await to avoid blocking)
      AnalyticsService.logProfileUndo(_lastAction!);

      debugPrint('Undo: Calling undoLastActionSilent...');
      // Remove the action from preferences using silent version to avoid triggering rebuild
      await prefsService.undoLastActionSilent();
      debugPrint('Undo: undoLastActionSilent completed');

      if (!mounted) {
        debugPrint('Undo: Widget unmounted after prefs update');
        return;
      }

      // Calculate new index before setState
      final newIndex = _currentProfileIndex > 0 ? _currentProfileIndex - 1 : 0;

      debugPrint('Undo: Setting new index to $newIndex (was $_currentProfileIndex)');
      debugPrint('Undo: Profiles list length: ${_filteredProfiles.length}');

      if (newIndex >= _filteredProfiles.length) {
        debugPrint('Undo: ERROR - newIndex $newIndex >= profiles length ${_filteredProfiles.length}');
        return;
      }

      setState(() {
        _currentProfileIndex = newIndex;
        _currentPhotoIndex = 0;
        _showUndoButton = false;
        _lastProfile = null;
        _lastAction = null;
        _lastMatch = null;
      });

      debugPrint('Undo: setState completed');

      // Save index after setState
      _saveCurrentIndex();

      debugPrint('Undo: Completed successfully. New index: $_currentProfileIndex');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action undone'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('Undo: Error - $e');
      debugPrint('Undo: Stack trace - $stack');
    }
  }

  void _saveCurrentIndex() {
    final prefsService = context.read<DiscoveryPreferencesService>();
    prefsService.saveCurrentIndex(_currentProfileIndex);
  }

  void _showEndOfProfilesMessage() {
    final prefsService = context.read<DiscoveryPreferencesService>();
    final hasFilters = prefsService.filters.hasActiveFilters;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('No More Profiles'),
        content: Text(
          hasFilters
              ? 'No more profiles match your current filters. Try adjusting your filters or check back later!'
              : 'You\'ve seen all available profiles for now. Check back later for more matches!',
        ),
        actions: [
          if (hasFilters) ...[
            VlvtButton.text(
              label: 'Clear Filters',
              onPressed: () async {
                Navigator.pop(context);
                // Reset all filters to defaults
                await prefsService.clearFilters();
                await _loadProfiles();
              },
            ),
            VlvtButton.text(
              label: 'Adjust Filters',
              onPressed: () {
                Navigator.pop(context);
                _navigateToFilters();
              },
            ),
          ],
          VlvtButton.text(
            label: 'Show All Again',
            onPressed: () async {
              Navigator.pop(context);
              await prefsService.clearSeenProfiles();
              await _loadProfiles();
            },
          ),
          VlvtButton.text(
            label: 'OK',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToFilters() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const DiscoveryFiltersScreen(),
      ),
    );

    if (!mounted) return;

    // If filters were changed, reload profiles
    if (result == true) {
      final prefsService = context.read<DiscoveryPreferencesService>();
      final filters = prefsService.filters;

      // Track filters applied
      // Note: Firebase Analytics only accepts String or num values
      await AnalyticsService.logFiltersApplied({
        'min_age': filters.minAge,
        'max_age': filters.maxAge,
        'max_distance': filters.maxDistance,
        'interests_count': filters.selectedInterests.length,
        'has_active_filters': filters.hasActiveFilters ? 1 : 0,
      });

      _currentProfileIndex = 0;
      await _loadProfiles();
    }
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _cardAnimationController.forward();
      } else {
        _cardAnimationController.reverse();
      }
    });
  }

  int get _remainingProfiles {
    if (_filteredProfiles.isEmpty) return 0;
    return _filteredProfiles.length - _currentProfileIndex;
  }

  void _dismissTutorial() {
    final prefsService = context.read<DiscoveryPreferencesService>();
    prefsService.markTutorialAsSeen();
    setState(() {
      _showTutorial = false;
    });
  }

  Widget _buildSwipeHint() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.3, end: 1.0),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeInOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: child,
        );
      },
      onEnd: () {
        // Repeat animation
        if (mounted) {
          setState(() {});
        }
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.arrow_back,
            color: VlvtColors.crimson.withValues(alpha: 0.6),
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Swipe to interact',
            style: TextStyle(
              fontSize: 14,
              color: VlvtColors.textSecondary.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
              fontFamily: 'Montserrat',
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.arrow_forward,
            color: VlvtColors.success.withValues(alpha: 0.6),
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCardContent(Profile profile) {
    return Card(
      elevation: 8,
      color: VlvtColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: VlvtColors.gold.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              VlvtColors.primary.withValues(alpha: 0.4),
              VlvtColors.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Photo carousel or default icon
                if (profile.photos != null && profile.photos!.isNotEmpty) ...[
                  Builder(
                    builder: (context) {
                      _initPhotoController(profile.photos!.length);
                      return Column(
                        children: [
                          SizedBox(
                            height: 300,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: PageView.builder(
                                controller: _photoPageController,
                                onPageChanged: (index) {
                                  // Subtle haptic for photo scroll
                                  HapticFeedback.selectionClick();
                                  setState(() {
                                    _currentPhotoIndex = index;
                                  });
                                },
                                itemCount: profile.photos!.length,
                                itemBuilder: (context, index) {
                                  final photoUrl = profile.photos![index];
                                  final profileService = context.read<ProfileApiService>();
                                  return Hero(
                                    tag: 'discovery_${profile.userId}', // Unique tag for discovery screen
                                    child: CachedNetworkImage(
                                      imageUrl: photoUrl.startsWith('http')
                                          ? photoUrl
                                          : '${profileService.baseUrl}$photoUrl',
                                      fit: BoxFit.cover,
                                      alignment: _getParallaxAlignment(), // Parallax effect on drag
                                      memCacheWidth: 800, // Optimize memory: 400px * 2x DPR
                                      placeholder: (context, url) => Container(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        child: const Center(
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                      errorWidget: (context, url, error) => Container(
                                        color: Colors.white.withValues(alpha: 0.2),
                                        child: const Icon(
                                          Icons.broken_image,
                                          size: 80,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          if (profile.photos!.length > 1) ...[
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(
                                profile.photos!.length,
                                (index) => Container(
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _currentPhotoIndex == index
                                        ? Colors.white
                                        : Colors.white.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ] else
                  const Icon(
                    Icons.person,
                    size: 120,
                    color: Colors.white,
                  ),
                const SizedBox(height: 24),
                Text(
                  '${profile.name ?? 'Anonymous'}, ${profile.age ?? '?'}',
                  style: VlvtTextStyles.displayMedium.copyWith(
                    color: VlvtColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  profile.bio ?? 'No bio available',
                  textAlign: TextAlign.center,
                  style: VlvtTextStyles.bodyLarge.copyWith(
                    color: VlvtColors.textSecondary,
                  ),
                ),
                if (profile.interests != null && profile.interests!.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Divider(color: VlvtColors.gold.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    'Interests',
                    style: VlvtTextStyles.h3.copyWith(
                      color: VlvtColors.gold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: profile.interests!.map((interest) {
                      return Chip(
                        label: Text(interest),
                        backgroundColor: VlvtColors.gold.withValues(alpha: 0.15),
                        labelStyle: VlvtTextStyles.labelSmall.copyWith(
                          color: VlvtColors.gold,
                        ),
                        side: BorderSide(
                          color: VlvtColors.gold.withValues(alpha: 0.3),
                        ),
                      );
                    }).toList(),
                  ),
                ],
                if (_isExpanded) ...[
                  const SizedBox(height: 24),
                  Divider(color: VlvtColors.gold.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline, color: VlvtColors.textSecondary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'More Info',
                        style: VlvtTextStyles.labelMedium.copyWith(
                          color: VlvtColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    profile.distance != null
                        ? 'Distance: ${LocationService.formatDistance(profile.distance! * 1000)}' // Convert km to meters
                        : 'Distance: Not available',
                    style: VlvtTextStyles.bodyMedium.copyWith(color: VlvtColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap card to collapse',
                    style: VlvtTextStyles.bodySmall.copyWith(color: VlvtColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileCard(Profile profile) {
    return ScaleTransition(
      scale: _cardAnimation.drive(Tween(begin: 1.0, end: 1.02)),
      child: _buildProfileCardContent(profile),
    );
  }

  @override
  Widget build(BuildContext context) {
    final prefsService = context.watch<DiscoveryPreferencesService>();
    final subscriptionService = context.watch<SubscriptionService>();
    final hasActiveFilters = prefsService.filters.hasActiveFilters;
    final likesRemaining = subscriptionService.getLikesRemaining();
    final showLikesCounter = subscriptionService.isFreeUser;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: VlvtColors.background,
        appBar: AppBar(
          backgroundColor: VlvtColors.background,
          title: Text('Discovery', style: VlvtTextStyles.h2),
          actions: [
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: hasActiveFilters ? VlvtColors.gold : VlvtColors.textSecondary,
              ),
              onPressed: _navigateToFilters,
            ),
          ],
        ),
        body: const Center(child: VlvtLoader()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        backgroundColor: VlvtColors.background,
        appBar: AppBar(
          backgroundColor: VlvtColors.background,
          title: Text('Discovery', style: VlvtTextStyles.h2),
          actions: [
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: hasActiveFilters ? VlvtColors.gold : VlvtColors.textSecondary,
              ),
              onPressed: _navigateToFilters,
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: VlvtColors.crimson),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage!,
                  style: VlvtTextStyles.bodyMedium.copyWith(color: VlvtColors.crimson),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              VlvtButton.primary(
                label: 'Retry',
                onPressed: _loadProfiles,
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredProfiles.isEmpty || _currentProfileIndex >= _filteredProfiles.length) {
      return Scaffold(
        backgroundColor: VlvtColors.background,
        appBar: AppBar(
          backgroundColor: VlvtColors.background,
          title: Text('Discovery', style: VlvtTextStyles.h2),
          actions: [
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: hasActiveFilters ? VlvtColors.gold : VlvtColors.textSecondary,
              ),
              onPressed: _navigateToFilters,
            ),
          ],
        ),
        body: DiscoveryEmptyState.noProfiles(
          context: context,
          hasFilters: hasActiveFilters,
          onAdjustFilters: _navigateToFilters,
          onShowAllProfiles: () async {
            await prefsService.clearSeenProfiles();
            _currentProfileIndex = 0;
            await _loadProfiles();
          },
        ),
      );
    }

    final profile = _filteredProfiles[_currentProfileIndex];

    return Scaffold(
      backgroundColor: VlvtColors.background,
      appBar: AppBar(
        backgroundColor: VlvtColors.background,
        title: Column(
          children: [
            Text('Discovery', style: VlvtTextStyles.h2),
            if (_remainingProfiles > 0)
              Text(
                '$_remainingProfiles profile${_remainingProfiles == 1 ? '' : 's'} left',
                style: VlvtTextStyles.labelSmall.copyWith(color: VlvtColors.textSecondary),
              ),
          ],
        ),
        actions: [
          if (showLikesCounter)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: likesRemaining > 0
                        ? VlvtColors.success.withValues(alpha: 0.2)
                        : VlvtColors.crimson.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: likesRemaining > 0
                          ? VlvtColors.success
                          : VlvtColors.crimson,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite,
                        size: 16,
                        color: likesRemaining > 0
                            ? VlvtColors.success
                            : VlvtColors.crimson,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likesRemaining',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Montserrat',
                          color: likesRemaining > 0
                              ? VlvtColors.success
                              : VlvtColors.crimson,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (hasActiveFilters)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: VlvtColors.gold,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Filtered',
                    style: TextStyle(
                      fontSize: 11,
                      color: VlvtColors.textOnGold,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Montserrat',
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: hasActiveFilters ? VlvtColors.gold : VlvtColors.textSecondary,
            ),
            onPressed: _navigateToFilters,
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Profile Counter Warning
                if (_remainingProfiles > 0 && _remainingProfiles <= 5)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: VlvtColors.gold.withValues(alpha: 0.15),
                    child: Text(
                      'Only $_remainingProfiles profile${_remainingProfiles == 1 ? '' : 's'} remaining. Adjust filters for more!',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Montserrat',
                        color: VlvtColors.gold,
                      ),
                    ),
                  ),

                // Profile Card with depth effect
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Stack(
                      children: [
                        // Shadow card behind (showing depth - more profiles available)
                        if (_currentProfileIndex < _filteredProfiles.length - 1)
                          Positioned(
                            top: 8,
                            left: 8,
                            right: 8,
                            bottom: 0,
                            child: Card(
                              elevation: 4,
                              color: VlvtColors.surface.withValues(alpha: 0.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: VlvtColors.gold.withValues(alpha: 0.15),
                                  width: 1,
                                ),
                              ),
                              child: Container(), // Empty shadow card
                            ),
                          ),
                        // Main card
                        GestureDetector(
                          onPanStart: _onPanStart,
                          onPanUpdate: _onPanUpdate,
                          onPanEnd: _onPanEnd,
                          onTap: _toggleExpanded,
                          child: AnimatedBuilder(
                            animation: _swipeAnimationController,
                            child: _buildProfileCard(profile),
                            builder: (context, child) {
                              final position = _swipeAnimationController.isAnimating
                                  ? _swipeAnimation.value
                                  : _cardPosition;

                              final opacity = _isDragging || _swipeAnimationController.isAnimating
                                  ? (1.0 - (position.dx.abs() / 300)).clamp(0.5, 1.0)
                                  : 1.0;

                              final cardWithIndicators = Stack(
                                children: [
                                  child!,
                                  if (_isDragging || _swipeAnimationController.isAnimating) ...[
                                    if (position.dx > 50)
                                      Positioned(
                                        top: 50,
                                        left: 30,
                                        child: Transform.rotate(
                                          angle: -0.5,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: VlvtColors.success,
                                                width: 4,
                                              ),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'LIKE',
                                              style: TextStyle(
                                                color: VlvtColors.success,
                                                fontSize: 32,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Montserrat',
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black.withValues(alpha: 0.3),
                                                    blurRadius: 4,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (position.dx < -50)
                                      Positioned(
                                        top: 50,
                                        right: 30,
                                        child: Transform.rotate(
                                          angle: 0.5,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24,
                                              vertical: 12,
                                            ),
                                            decoration: BoxDecoration(
                                              border: Border.all(
                                                color: VlvtColors.crimson,
                                                width: 4,
                                              ),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'PASS',
                                              style: TextStyle(
                                                color: VlvtColors.crimson,
                                                fontSize: 32,
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Montserrat',
                                                shadows: [
                                                  Shadow(
                                                    color: Colors.black.withValues(alpha: 0.3),
                                                    blurRadius: 4,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                  ],
                                ],
                              );

                              return _ShakeWidget(
                                isShaking: _isShaking,
                                child: Transform.translate(
                                  offset: position,
                                  child: Transform.rotate(
                                    angle: _cardRotation,
                                    child: Opacity(
                                      opacity: opacity,
                                      child: cardWithIndicators,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ], // Stack children
                    ), // Stack
                  ),
                ),

                // Action Buttons - Made less prominent to encourage swiping
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Pass button - smaller and semi-transparent
                      Opacity(
                        opacity: 0.7,
                        child: FloatingActionButton(
                          heroTag: 'pass',
                          mini: true,
                          onPressed: () {
                            final subService = context.read<SubscriptionService>();
                            if (!subService.hasPremiumAccess) {
                              HapticFeedback.heavyImpact();
                              PremiumGateDialog.showSwipingRequired(context);
                              return;
                            }
                            HapticFeedback.lightImpact();
                            _onPass();
                          },
                          backgroundColor: VlvtColors.crimson,
                          child: const Icon(Icons.close, size: 24, color: Colors.white),
                        ),
                      ),
                      if (_showUndoButton)
                        FloatingActionButton(
                          heroTag: 'undo',
                          mini: true,
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _onUndo();
                          },
                          backgroundColor: VlvtColors.primary,
                          child: const Icon(Icons.undo, size: 20, color: Colors.white),
                        ),
                      // Like button - smaller and semi-transparent
                      Opacity(
                        opacity: 0.7,
                        child: FloatingActionButton(
                          heroTag: 'like',
                          mini: true,
                          onPressed: () {
                            final subService = context.read<SubscriptionService>();
                            if (!subService.hasPremiumAccess) {
                              HapticFeedback.heavyImpact();
                              PremiumGateDialog.showSwipingRequired(context);
                              return;
                            }
                            HapticFeedback.mediumImpact();
                            _onLike();
                          },
                          backgroundColor: VlvtColors.success,
                          child: const Icon(Icons.favorite, size: 24, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),

                // Swipe hint for first-time users
                if (!_isDragging && !prefsService.hasSeenTutorial && !_showTutorial)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _buildSwipeHint(),
                  ),
              ],
            ),

            // Undo Button Hint
            if (_showUndoButton)
              Positioned(
                bottom: 100,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: VlvtColors.primary,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      'Tap UNDO to revert last action',
                      style: VlvtTextStyles.labelMedium.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),

            // Heart particles animation
            if (_showHeartParticles)
              Positioned.fill(
                child: HeartParticleAnimation(
                  onComplete: () {
                    if (mounted) {
                      setState(() {
                        _showHeartParticles = false;
                      });
                    }
                  },
                ),
              ),

            // Match overlay
            if (_matchOverlayUserName != null && _matchOverlayIsNewMatch != null)
              Positioned.fill(
                child: MatchOverlay(
                  userName: _matchOverlayUserName!,
                  isNewMatch: _matchOverlayIsNewMatch!,
                  onDismiss: () {
                    if (mounted) {
                      setState(() {
                        _matchOverlayUserName = null;
                        _matchOverlayIsNewMatch = null;
                      });
                    }
                  },
                ),
              ),

            // Tutorial overlay
            if (_showTutorial)
              Positioned.fill(
                child: SwipeTutorialOverlay(
                  onDismiss: _dismissTutorial,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shake animation widget for pass interactions
class _ShakeWidget extends StatefulWidget {
  final bool isShaking;
  final Widget child;

  const _ShakeWidget({
    required this.isShaking,
    required this.child,
  });

  @override
  State<_ShakeWidget> createState() => _ShakeWidgetState();
}

class _ShakeWidgetState extends State<_ShakeWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _animation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticIn,
    ));
  }

  @override
  void didUpdateWidget(_ShakeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isShaking && !oldWidget.isShaking) {
      // Defer animation start to next frame to avoid layout conflicts
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isShaking) {
          _controller.forward(from: 0.0);
        }
      });
    } else if (!widget.isShaking && oldWidget.isShaking) {
      // Stop animation if shaking is turned off - also defer to avoid conflicts
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _controller.stop();
          _controller.reset();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_animation.value, 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
