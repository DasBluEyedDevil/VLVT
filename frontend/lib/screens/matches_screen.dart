import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/chat_api_service.dart';
import '../services/profile_api_service.dart';
import '../models/match.dart';
import '../models/profile.dart';
import '../widgets/vlvt_loader.dart';
import '../theme/vlvt_colors.dart';
import '../theme/vlvt_text_styles.dart';
import 'chat_screen.dart';

/// Match status type for filtering
enum MatchStatus { mutual, likedYou, liked }

/// Filter type for the matches screen
enum MatchFilterType { all, mutual, likedYou, liked }

/// Data model for a match entry (combines likes and actual matches)
class MatchEntry {
  final String odId;
  final Profile? profile;
  final MatchStatus status;
  final Match? match; // Only for mutual matches
  final DateTime createdAt;

  MatchEntry({
    required this.odId,
    this.profile,
    required this.status,
    this.match,
    required this.createdAt,
  });
}

/// MatchesScreen - displays likes activity (who liked you, who you liked, mutual matches)
class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  bool _isLoading = false;
  String? _error;

  // Data
  List<MatchEntry> _allEntries = [];
  MatchFilterType _activeFilter = MatchFilterType.all;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authService = context.read<AuthService>();
      final profileService = context.read<ProfileApiService>();
      final chatService = context.read<ChatApiService>();
      final userId = authService.userId;

      if (userId == null) {
        throw Exception('User not authenticated');
      }

      final List<MatchEntry> entries = [];

      // 1. Get mutual matches
      final matches = await chatService.getMatches(userId);
      final matchedUserIds = <String>{};

      for (final match in matches) {
        final otherUserId = match.getOtherUserId(userId);
        matchedUserIds.add(otherUserId);

        Profile? profile;
        try {
          profile = await profileService.getProfile(otherUserId);
        } catch (e) {
          debugPrint('Failed to load profile for $otherUserId: $e');
        }

        entries.add(MatchEntry(
          odId: otherUserId,
          profile: profile,
          status: MatchStatus.mutual,
          match: match,
          createdAt: match.createdAt,
        ));
      }

      // 2. Get users who liked the current user (received likes)
      try {
        final receivedLikes = await profileService.getReceivedLikes();
        for (final like in receivedLikes) {
          final likerUserId = like['userId'] as String;

          // Skip if already matched
          if (matchedUserIds.contains(likerUserId)) continue;

          Profile? profile;
          try {
            profile = await profileService.getProfile(likerUserId);
          } catch (e) {
            debugPrint('Failed to load profile for $likerUserId: $e');
          }

          entries.add(MatchEntry(
            odId: likerUserId,
            profile: profile,
            status: MatchStatus.likedYou,
            createdAt: DateTime.tryParse(like['likedAt'] as String? ?? '') ?? DateTime.now(),
          ));
        }
      } catch (e) {
        debugPrint('Failed to load received likes: $e');
      }

      // 3. Get users the current user liked (sent likes) - requires backend endpoint
      try {
        final sentLikes = await profileService.getSentLikes();
        for (final like in sentLikes) {
          final targetUserId = like['target_user_id'] as String;

          // Skip if already matched
          if (matchedUserIds.contains(targetUserId)) continue;

          Profile? profile;
          try {
            profile = await profileService.getProfile(targetUserId);
          } catch (e) {
            debugPrint('Failed to load profile for $targetUserId: $e');
          }

          entries.add(MatchEntry(
            odId: targetUserId,
            profile: profile,
            status: MatchStatus.liked,
            createdAt: DateTime.tryParse(like['created_at'] as String? ?? '') ?? DateTime.now(),
          ));
        }
      } catch (e) {
        debugPrint('Failed to load sent likes: $e');
      }

      // Sort by created date (most recent first)
      entries.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _allEntries = entries;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<MatchEntry> get _filteredEntries {
    if (_activeFilter == MatchFilterType.all) {
      return _allEntries;
    }

    return _allEntries.where((entry) {
      switch (_activeFilter) {
        case MatchFilterType.mutual:
          return entry.status == MatchStatus.mutual;
        case MatchFilterType.likedYou:
          return entry.status == MatchStatus.likedYou;
        case MatchFilterType.liked:
          return entry.status == MatchStatus.liked;
        case MatchFilterType.all:
          return true;
      }
    }).toList();
  }

  int get _mutualCount => _allEntries.where((e) => e.status == MatchStatus.mutual).length;
  int get _likedYouCount => _allEntries.where((e) => e.status == MatchStatus.likedYou).length;
  int get _likedCount => _allEntries.where((e) => e.status == MatchStatus.liked).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VlvtColors.background,
      body: RefreshIndicator(
        color: VlvtColors.gold,
        onRefresh: _loadData,
        child: CustomScrollView(
          slivers: [
            // Header
            SliverAppBar(
              expandedHeight: 100.0,
              floating: true,
              pinned: true,
              backgroundColor: VlvtColors.background,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  'Matches',
                  style: VlvtTextStyles.h2.copyWith(
                    fontFamily: 'PlayfairDisplay',
                    fontStyle: FontStyle.italic,
                  ),
                ),
                centerTitle: false,
                titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              ),
            ),

            // Stats summary
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  '$_mutualCount matches  •  $_likedYouCount likes you  •  $_likedCount liked',
                  textAlign: TextAlign.center,
                  style: VlvtTextStyles.labelMedium.copyWith(
                    color: VlvtColors.textMuted,
                  ),
                ),
              ),
            ),

            // Filter tabs
            SliverToBoxAdapter(
              child: _buildFilterTabs(),
            ),

            // Content
            ..._buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabs() {
    final filters = [
      _FilterTab(type: MatchFilterType.all, label: 'All', icon: Icons.favorite),
      _FilterTab(type: MatchFilterType.mutual, label: 'Matches', icon: Icons.favorite),
      _FilterTab(type: MatchFilterType.likedYou, label: 'Likes You', icon: Icons.auto_awesome),
      _FilterTab(type: MatchFilterType.liked, label: 'You Liked', icon: Icons.favorite_border),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: filters.map((filter) {
          final isActive = _activeFilter == filter.type;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _activeFilter = filter.type;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive ? VlvtColors.gold : VlvtColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: isActive ? VlvtColors.gold : VlvtColors.border,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        filter.icon,
                        size: 14,
                        color: isActive ? VlvtColors.textOnGold : VlvtColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          filter.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'Montserrat',
                            color: isActive ? VlvtColors.textOnGold : VlvtColors.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildContent() {
    if (_isLoading) {
      return [
        const SliverFillRemaining(
          child: Center(child: VlvtLoader()),
        ),
      ];
    }

    if (_error != null) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: VlvtColors.crimson),
                const SizedBox(height: 16),
                Text(
                  'Error loading matches',
                  style: VlvtTextStyles.h3.copyWith(color: VlvtColors.crimson),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: VlvtTextStyles.bodySmall.copyWith(color: VlvtColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final entries = _filteredEntries;

    if (entries.isEmpty) {
      return [
        SliverFillRemaining(
          child: _buildEmptyState(),
        ),
      ];
    }

    // Grid of match cards
    return [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.75,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildMatchCard(entries[index]),
            childCount: entries.length,
          ),
        ),
      ),
    ];
  }

  Widget _buildEmptyState() {
    IconData icon;
    String title;
    String subtitle;

    switch (_activeFilter) {
      case MatchFilterType.all:
        icon = Icons.favorite_outline;
        title = 'No Matches Yet';
        subtitle = 'Keep swiping to find your perfect match!';
        break;
      case MatchFilterType.mutual:
        icon = Icons.favorite;
        title = 'No Matches Yet';
        subtitle = 'When you and someone like each other, they\'ll appear here.';
        break;
      case MatchFilterType.likedYou:
        icon = Icons.auto_awesome;
        title = 'No Likes Yet';
        subtitle = 'Complete your profile to attract more likes!';
        break;
      case MatchFilterType.liked:
        icon = Icons.favorite_border;
        title = 'No Likes Yet';
        subtitle = 'Swipe right on profiles you like!';
        break;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 80, color: VlvtColors.textMuted),
            const SizedBox(height: 24),
            Text(
              title,
              style: VlvtTextStyles.h2.copyWith(color: VlvtColors.gold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: VlvtTextStyles.bodyMedium.copyWith(color: VlvtColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchCard(MatchEntry entry) {
    final profile = entry.profile;
    final name = profile?.name ?? 'User';
    final age = profile?.age?.toString() ?? '?';
    final bio = profile?.bio ?? '';
    final photoUrl = profile?.photos?.isNotEmpty == true ? profile!.photos!.first : null;

    return GestureDetector(
      onTap: () => _handleCardTap(entry),
      child: Container(
        decoration: BoxDecoration(
          color: VlvtColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: VlvtColors.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Photo
            if (photoUrl != null)
              CachedNetworkImage(
                imageUrl: photoUrl.startsWith('http')
                    ? photoUrl
                    : '${context.read<ProfileApiService>().baseUrl}$photoUrl',
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: VlvtColors.surfaceElevated,
                  child: const Center(
                    child: CircularProgressIndicator(color: VlvtColors.gold),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: VlvtColors.surfaceElevated,
                  child: Icon(Icons.person, size: 48, color: VlvtColors.textMuted),
                ),
              )
            else
              Container(
                color: VlvtColors.surfaceElevated,
                child: Icon(Icons.person, size: 48, color: VlvtColors.textMuted),
              ),

            // Gradient overlay at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$name, $age',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Montserrat',
                      ),
                    ),
                    if (bio.isNotEmpty)
                      Text(
                        bio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 12,
                          fontFamily: 'Montserrat',
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Status indicator
            Positioned(
              top: 8,
              right: 8,
              child: _buildStatusIndicator(entry.status),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(MatchStatus status) {
    Color bgColor;
    IconData icon;
    Color iconColor;

    switch (status) {
      case MatchStatus.mutual:
        bgColor = VlvtColors.gold;
        icon = Icons.favorite;
        iconColor = VlvtColors.textOnGold;
        break;
      case MatchStatus.likedYou:
        bgColor = VlvtColors.crimson;
        icon = Icons.auto_awesome;
        iconColor = Colors.white;
        break;
      case MatchStatus.liked:
        bgColor = VlvtColors.success;
        icon = Icons.favorite_border;
        iconColor = Colors.white;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: bgColor.withValues(alpha: 0.4),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Icon(icon, size: 16, color: iconColor),
    );
  }

  void _handleCardTap(MatchEntry entry) async {
    HapticFeedback.lightImpact();

    if (entry.status == MatchStatus.mutual && entry.match != null) {
      // Navigate to chat for mutual matches
      final shouldRefresh = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(match: entry.match!),
        ),
      );

      if (shouldRefresh == true && mounted) {
        _loadData();
      }
    } else if (entry.status == MatchStatus.likedYou) {
      // Show profile of person who liked you
      // For now, just show a snackbar - could navigate to profile detail
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${entry.profile?.name ?? "Someone"} likes you! Swipe right to match.'),
          backgroundColor: VlvtColors.crimson,
        ),
      );
    } else if (entry.status == MatchStatus.liked) {
      // Show profile of person you liked
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Waiting for ${entry.profile?.name ?? "them"} to like you back!'),
          backgroundColor: VlvtColors.success,
        ),
      );
    }
  }
}

class _FilterTab {
  final MatchFilterType type;
  final String label;
  final IconData icon;

  _FilterTab({required this.type, required this.label, required this.icon});
}
