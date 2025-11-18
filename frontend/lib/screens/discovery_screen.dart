import 'package:flutter/material.dart';
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
import '../models/profile.dart';
import '../models/match.dart';
import 'discovery_filters_screen.dart';
import 'dart:async';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> with SingleTickerProviderStateMixin {
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
        if (alreadyExists) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You already matched with ${profile.name ?? "user"}!'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Matched with ${profile.name ?? "user"}!'),
              backgroundColor: Colors.green,
            ),
          );
        }
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

    // Move to next profile and show undo button
    _moveToNextProfile();
    _showUndo();
  }

  void _moveToNextProfile() {
    setState(() {
      if (_currentProfileIndex < _filteredProfiles.length - 1) {
        _currentProfileIndex++;
        _currentPhotoIndex = 0;
        _photoPageController?.dispose();
        _photoPageController = null;
        _saveCurrentIndex();
      } else {
        _showEndOfProfilesMessage();
      }
    });
  }

  void _initPhotoController(int photoCount) {
    if (_photoPageController == null && photoCount > 0) {
      _photoPageController = PageController(initialPage: 0);
    }
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
    setState(() {
      _isDragging = true;
    });
  }

  void _onPanUpdate(DragUpdateDetails details) {
    setState(() {
      _cardPosition += details.delta;

      // Calculate rotation based on horizontal position (max 20 degrees)
      _cardRotation = (_cardPosition.dx / 1000).clamp(-0.35, 0.35);
    });
  }

  void _onPanEnd(DragEndDetails details) {
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
        // Reset card position
        setState(() {
          _cardPosition = Offset.zero;
          _cardRotation = 0.0;
        });
        _swipeAnimationController.reset();

        // Trigger appropriate action
        if (swipeRight) {
          _onLike();
        } else {
          _onPass();
        }
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
        setState(() {
          _cardPosition = Offset.zero;
          _cardRotation = 0.0;
        });
        _swipeAnimationController.reset();
      });
    }
  }

  Future<void> _onUndo() async {
    if (_lastProfile == null || _lastAction == null) return;

    _undoTimer?.cancel();

    final prefsService = context.read<DiscoveryPreferencesService>();

    // Track undo event
    await AnalyticsService.logProfileUndo(_lastAction!);

    // Undo the last action in preferences
    await prefsService.undoLastAction();

    // Go back to previous profile
    setState(() {
      if (_currentProfileIndex > 0) {
        _currentProfileIndex--;
      }
      _showUndoButton = false;
      _lastProfile = null;
      _lastAction = null;
      _lastMatch = null;
      _saveCurrentIndex();
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Action undone'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.blue,
        ),
      );
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
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                // Reset all filters to defaults
                await prefsService.clearFilters();
                await _loadProfiles();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.deepPurple,
                fontWeight: FontWeight.bold,
              ),
              child: const Text('Clear Filters'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _navigateToFilters();
              },
              child: const Text('Adjust Filters'),
            ),
          ],
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await prefsService.clearSeenProfiles();
              await _loadProfiles();
            },
            child: const Text('Show All Again'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
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

    // If filters were changed, reload profiles
    if (result == true) {
      final prefsService = context.read<DiscoveryPreferencesService>();
      final filters = prefsService.filters;

      // Track filters applied
      await AnalyticsService.logFiltersApplied({
        'min_age': filters.minAge,
        'max_age': filters.maxAge,
        'max_distance': filters.maxDistance,
        'interests_count': filters.selectedInterests.length,
        'has_active_filters': filters.hasActiveFilters,
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

  @override
  Widget build(BuildContext context) {
    final prefsService = context.watch<DiscoveryPreferencesService>();
    final subscriptionService = context.watch<SubscriptionService>();
    final hasActiveFilters = prefsService.filters.hasActiveFilters;
    final likesRemaining = subscriptionService.getLikesRemaining();
    final showLikesCounter = subscriptionService.isDemoMode;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Discovery'),
          actions: [
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: hasActiveFilters ? Colors.amber : null,
              ),
              onPressed: _navigateToFilters,
            ),
          ],
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Discovery'),
          actions: [
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: hasActiveFilters ? Colors.amber : null,
              ),
              onPressed: _navigateToFilters,
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(fontSize: 16, color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadProfiles,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredProfiles.isEmpty || _currentProfileIndex >= _filteredProfiles.length) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Discovery'),
          actions: [
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: hasActiveFilters ? Colors.amber : null,
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
      appBar: AppBar(
        title: Column(
          children: [
            const Text('Discovery'),
            if (_remainingProfiles > 0)
              Text(
                '$_remainingProfiles profile${_remainingProfiles == 1 ? '' : 's'} left',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
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
                    color: likesRemaining > 0 ? Colors.green.shade100 : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: likesRemaining > 0 ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.favorite,
                        size: 16,
                        color: likesRemaining > 0 ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likesRemaining',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: likesRemaining > 0 ? Colors.green.shade900 : Colors.red.shade900,
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
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Filtered',
                    style: TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: hasActiveFilters ? Colors.amber : null,
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
                    color: Colors.orange.shade100,
                    child: Text(
                      'Only $_remainingProfiles profile${_remainingProfiles == 1 ? '' : 's'} remaining. Adjust filters for more!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                  ),

                // Profile Card
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: GestureDetector(
                      onPanStart: _onPanStart,
                      onPanUpdate: _onPanUpdate,
                      onPanEnd: _onPanEnd,
                      onTap: _toggleExpanded,
                      child: AnimatedBuilder(
                        animation: _swipeAnimationController.isAnimating
                          ? _swipeAnimation
                          : AlwaysStoppedAnimation(Offset.zero),
                        builder: (context, child) {
                          // Use animated position if animating, otherwise use dragged position
                          final position = _swipeAnimationController.isAnimating
                              ? _swipeAnimation.value
                              : _cardPosition;

                          // Calculate opacity based on swipe distance
                          final opacity = _isDragging || _swipeAnimationController.isAnimating
                              ? (1.0 - (position.dx.abs() / 300)).clamp(0.5, 1.0)
                              : 1.0;

                          return Transform.translate(
                            offset: position,
                            child: Transform.rotate(
                              angle: _cardRotation,
                              child: Opacity(
                                opacity: opacity,
                                child: AnimatedBuilder(
                                  animation: _cardAnimation,
                                  builder: (context, child) {
                                    return Card(
                                      elevation: 8,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Stack(
                                        children: [
                                          Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.deepPurple.shade100,
                                    Colors.deepPurple.shade300,
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
                                                        setState(() {
                                                          _currentPhotoIndex = index;
                                                        });
                                                      },
                                                      itemCount: profile.photos!.length,
                                                      itemBuilder: (context, index) {
                                                        final photoUrl = profile.photos![index];
                                                        final profileService = context.read<ProfileApiService>();
                                                        return CachedNetworkImage(
                                                          imageUrl: '${profileService.baseUrl}$photoUrl',
                                                          fit: BoxFit.cover,
                                                          placeholder: (context, url) => Container(
                                                            color: Colors.white.withOpacity(0.2),
                                                            child: const Center(
                                                              child: CircularProgressIndicator(
                                                                color: Colors.white,
                                                              ),
                                                            ),
                                                          ),
                                                          errorWidget: (context, url, error) => Container(
                                                            color: Colors.white.withOpacity(0.2),
                                                            child: const Icon(
                                                              Icons.broken_image,
                                                              size: 80,
                                                              color: Colors.white70,
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
                                                              : Colors.white.withOpacity(0.4),
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
                                        style: const TextStyle(
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 16),
                                      Text(
                                        profile.bio ?? 'No bio available',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (profile.interests != null && profile.interests!.isNotEmpty) ...[
                                        const SizedBox(height: 24),
                                        const Divider(color: Colors.white54),
                                        const SizedBox(height: 16),
                                        const Text(
                                          'Interests',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
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
                                              backgroundColor: Colors.white.withOpacity(0.2),
                                              labelStyle: const TextStyle(color: Colors.white),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                      if (_isExpanded) ...[
                                        const SizedBox(height: 24),
                                        const Divider(color: Colors.white54),
                                        const SizedBox(height: 16),
                                        const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.info_outline, color: Colors.white70, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'More Info',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white70,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          profile.distance != null
                                              ? 'Distance: ${LocationService.formatDistance(profile.distance! * 1000)}' // Convert km to meters
                                              : 'Distance: Not available',
                                          style: const TextStyle(color: Colors.white70),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Tap card to collapse',
                                          style: TextStyle(color: Colors.white54, fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Swipe direction indicators
                            if (_isDragging || _swipeAnimationController.isAnimating) ...[
                              // LIKE indicator (right swipe - green)
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
                                          color: Colors.green,
                                          width: 4,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'LIKE',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black.withOpacity(0.3),
                                              blurRadius: 4,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                              // PASS indicator (left swipe - red)
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
                                          color: Colors.red,
                                          width: 4,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'PASS',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black.withOpacity(0.3),
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
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ),
                                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // Action Buttons
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FloatingActionButton(
                        heroTag: 'pass',
                        onPressed: _onPass,
                        backgroundColor: Colors.red,
                        child: const Icon(Icons.close, size: 32),
                      ),
                      if (_showUndoButton)
                        FloatingActionButton(
                          heroTag: 'undo',
                          onPressed: _onUndo,
                          backgroundColor: Colors.blue,
                          child: const Icon(Icons.undo, size: 28),
                        ),
                      FloatingActionButton(
                        heroTag: 'like',
                        onPressed: _onLike,
                        backgroundColor: Colors.green,
                        child: const Icon(Icons.favorite, size: 32),
                      ),
                    ],
                  ),
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
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Text(
                      'Tap UNDO to revert last action',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
