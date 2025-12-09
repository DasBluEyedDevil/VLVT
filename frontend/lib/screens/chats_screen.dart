import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/chat_api_service.dart';
import '../services/profile_api_service.dart';
import '../services/cache_service.dart';
import '../services/safety_service.dart';
import '../models/match.dart';
import '../models/profile.dart';
import '../models/message.dart';
import '../utils/date_utils.dart';
import '../widgets/user_action_sheet.dart';
import '../widgets/vlvt_loader.dart';
import '../widgets/vlvt_input.dart';
import '../widgets/vlvt_button.dart';
import '../theme/vlvt_colors.dart';
import '../theme/vlvt_text_styles.dart';
import 'chat_screen.dart';

enum ChatsSortOption { recentActivity, newestMatches, nameAZ }

/// ChatsScreen - displays active conversations (mutual matches with messaging)
/// This is the renamed MatchesScreen, now focused on chat functionality
class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> {
  // State management
  bool _isLoading = false;
  String? _error;
  DateTime? _lastUpdated;

  // Data
  List<Match> _matches = [];
  Map<String, Profile> _profiles = {};
  Map<String, Message?> _lastMessages = {};
  Map<String, int> _unreadCounts = {};

  // Filtering and sorting
  String _searchQuery = '';
  ChatsSortOption _sortOption = ChatsSortOption.recentActivity;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Load all data: matches, profiles, and last messages
  Future<void> _loadData({bool forceRefresh = false}) async {
    final authService = context.read<AuthService>();
    final chatService = context.read<ChatApiService>();
    final profileService = context.read<ProfileApiService>();
    final cacheService = context.read<CacheService>();
    final safetyService = context.read<SafetyService>();
    final userId = authService.userId;

    if (userId == null) {
      setState(() {
        _error = 'User not authenticated';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load blocked users first
      await safetyService.loadBlockedUsers();

      // Step 1: Load matches (from cache or API)
      List<Match> matches;
      if (!forceRefresh) {
        final cachedMatches = cacheService.getCachedMatches(userId);
        if (cachedMatches != null) {
          matches = cachedMatches;
        } else {
          matches = await chatService.getMatches(userId);
          cacheService.cacheMatches(userId, matches);
        }
      } else {
        matches = await chatService.getMatches(userId);
        cacheService.cacheMatches(userId, matches);
      }

      // Step 2: Batch load all profiles (this fixes the N+1 query problem!)
      final userIds = matches
          .map((match) => match.getOtherUserId(userId))
          .toList();

      Map<String, Profile> profiles = {};
      if (userIds.isNotEmpty) {
        // Check cache first for each profile
        final uncachedUserIds = <String>[];
        for (final uid in userIds) {
          final cachedProfile = cacheService.getCachedProfile(uid);
          if (cachedProfile != null && !forceRefresh) {
            profiles[uid] = cachedProfile;
          } else {
            uncachedUserIds.add(uid);
          }
        }

        // Batch fetch uncached profiles
        if (uncachedUserIds.isNotEmpty) {
          final fetchedProfiles = await profileService.batchGetProfiles(uncachedUserIds);
          profiles.addAll(fetchedProfiles);
          cacheService.cacheProfiles(fetchedProfiles);
        }
      }

      // Step 3: Batch load last messages for preview
      final matchIds = matches.map((match) => match.id).toList();
      Map<String, Message?> lastMessages = {};
      if (matchIds.isNotEmpty) {
        // Check cache first
        final uncachedMatchIds = <String>[];
        for (final matchId in matchIds) {
          final cachedMessage = cacheService.getCachedLastMessage(matchId);
          if (cachedMessage != null && !forceRefresh) {
            lastMessages[matchId] = cachedMessage;
          } else {
            uncachedMatchIds.add(matchId);
          }
        }

        // Batch fetch uncached last messages
        if (uncachedMatchIds.isNotEmpty) {
          final fetchedMessages = await chatService.batchGetLastMessages(uncachedMatchIds);
          lastMessages.addAll(fetchedMessages);
          cacheService.cacheLastMessages(fetchedMessages);
        }
      }

      // Step 4: Fetch unread message counts
      Map<String, int> unreadCounts = {};
      try {
        unreadCounts = await chatService.getUnreadCounts(userId);
      } catch (e) {
        debugPrint('Failed to fetch unread counts: $e');
        // Continue without unread counts - not critical
      }

      setState(() {
        _matches = matches;
        _profiles = profiles;
        _lastMessages = lastMessages;
        _unreadCounts = unreadCounts;
        _isLoading = false;
        _lastUpdated = DateTime.now();
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Handle pull-to-refresh
  Future<void> _handleRefresh() async {
    await _loadData(forceRefresh: true);
  }

  /// Get filtered and sorted matches
  List<Match> _getFilteredAndSortedMatches() {
    final authService = context.read<AuthService>();
    final safetyService = context.read<SafetyService>();
    final userId = authService.userId;
    if (userId == null) return [];

    var filteredMatches = _matches;

    // Filter out blocked users
    filteredMatches = filteredMatches.where((match) {
      final otherUserId = match.getOtherUserId(userId);
      return !safetyService.isUserBlocked(otherUserId);
    }).toList();

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filteredMatches = filteredMatches.where((match) {
        final otherUserId = match.getOtherUserId(userId);
        final profile = _profiles[otherUserId];
        final name = profile?.name?.toLowerCase() ?? '';
        return name.contains(_searchQuery.toLowerCase());
      }).toList();
    }

    // Apply sorting
    switch (_sortOption) {
      case ChatsSortOption.recentActivity:
        // Sort by last message timestamp (most recent first)
        filteredMatches.sort((a, b) {
          final lastMessageA = _lastMessages[a.id];
          final lastMessageB = _lastMessages[b.id];
          if (lastMessageA == null && lastMessageB == null) {
            return b.createdAt.compareTo(a.createdAt);
          }
          if (lastMessageA == null) return 1;
          if (lastMessageB == null) return -1;
          return lastMessageB.timestamp.compareTo(lastMessageA.timestamp);
        });
        break;
      case ChatsSortOption.newestMatches:
        // Sort by match creation date (newest first)
        filteredMatches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case ChatsSortOption.nameAZ:
        // Sort alphabetically by name
        filteredMatches.sort((a, b) {
          final profileA = _profiles[a.getOtherUserId(userId)];
          final profileB = _profiles[b.getOtherUserId(userId)];
          final nameA = profileA?.name ?? 'User';
          final nameB = profileB?.name ?? 'User';
          return nameA.compareTo(nameB);
        });
        break;
    }

    return filteredMatches;
  }

  /// Show sort options dialog
  void _showSortDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VlvtColors.surfaceElevated,
        title: Text('Sort by', style: VlvtTextStyles.h3.copyWith(color: VlvtColors.gold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSortOption('Recent Activity', ChatsSortOption.recentActivity),
            _buildSortOption('Newest Matches', ChatsSortOption.newestMatches),
            _buildSortOption('Name (A-Z)', ChatsSortOption.nameAZ),
          ],
        ),
      ),
    );
  }

  Widget _buildSortOption(String title, ChatsSortOption value) {
    final isSelected = _sortOption == value;
    return ListTile(
      title: Text(
        title,
        style: VlvtTextStyles.bodyMedium.copyWith(
          color: isSelected ? VlvtColors.gold : VlvtColors.textPrimary,
        ),
      ),
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: isSelected ? VlvtColors.gold : VlvtColors.textMuted,
      ),
      onTap: () {
        setState(() {
          _sortOption = value;
        });
        Navigator.pop(context);
      },
    );
  }

  /// Handle unmatch action
  Future<void> _handleUnmatch(Match match) async {
    final authService = context.read<AuthService>();
    final chatService = context.read<ChatApiService>();
    final cacheService = context.read<CacheService>();
    final userId = authService.userId;
    if (userId == null) return;

    final otherUserId = match.getOtherUserId(userId);
    final profile = _profiles[otherUserId];
    final name = profile?.name ?? 'this user';

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: VlvtColors.surfaceElevated,
        title: Text('Unmatch', style: VlvtTextStyles.h2),
        content: Text(
          'Are you sure you want to unmatch with $name? This action cannot be undone.',
          style: VlvtTextStyles.bodyMedium,
        ),
        actions: [
          VlvtButton.text(
            label: 'Cancel',
            onPressed: () => Navigator.pop(context, false),
          ),
          VlvtButton.danger(
            label: 'Unmatch',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Optimistically update UI
    setState(() {
      _matches.removeWhere((m) => m.id == match.id);
      _profiles.remove(otherUserId);
      _lastMessages.remove(match.id);
    });

    // Show undo snackbar
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unmatched with $name'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              // Re-add the match
              setState(() {
                _matches.add(match);
                if (profile != null) {
                  _profiles[otherUserId] = profile;
                }
              });
            },
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }

    // Perform API call
    try {
      await chatService.unmatch(match.id);
      cacheService.invalidateMatches(userId);
      cacheService.invalidateMessages(match.id);
      cacheService.invalidateLastMessage(match.id);
    } catch (e) {
      // If API call fails, show error and restore the match
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unmatch: $e'),
            backgroundColor: VlvtColors.crimson,
          ),
        );
        setState(() {
          _matches.add(match);
          if (profile != null) {
            _profiles[otherUserId] = profile;
          }
        });
      }
    }
  }

  /// Show match action menu
  void _showMatchActions(Match match) {
    final authService = context.read<AuthService>();
    final userId = authService.userId;
    if (userId == null) return;

    final otherUserId = match.getOtherUserId(userId);
    final profile = _profiles[otherUserId];

    if (profile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile not available')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      builder: (context) => UserActionSheet(
        otherUserProfile: profile,
        match: match,
        onActionComplete: () {
          // Refresh the matches list after block/unmatch
          _loadData(forceRefresh: true);
        },
      ),
    );
  }

  /// Build match list item
  Widget _buildMatchItem(Match match, String userId) {
    final otherUserId = match.getOtherUserId(userId);
    final profile = _profiles[otherUserId];
    final name = profile?.name ?? 'User';
    final age = profile?.age?.toString() ?? '?';
    final lastMessage = _lastMessages[match.id];
    final unreadCount = _unreadCounts[match.id] ?? 0;

    String subtitle;
    if (lastMessage != null) {
      final messageText = lastMessage.text.length > 50
          ? '${lastMessage.text.substring(0, 50)}...'
          : lastMessage.text;
      subtitle = messageText;
    } else {
      subtitle = 'No messages yet';
    }

    return Dismissible(
      key: Key(match.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: VlvtColors.crimson,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Unmatch',
              style: VlvtTextStyles.labelMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.person_remove, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        await _handleUnmatch(match);
        return false; // We handle removal ourselves
      },
      child: ListTile(
        leading: Stack(
          children: [
            Hero(
              tag: 'avatar_$otherUserId', // Consistent tag for hero animation to ChatScreen
              child: CircleAvatar(
                backgroundColor: VlvtColors.primary,
                backgroundImage: profile?.photos?.isNotEmpty == true
                    ? CachedNetworkImageProvider(
                        profile!.photos!.first.startsWith('http')
                            ? profile.photos!.first
                            : '${context.read<ProfileApiService>().baseUrl}${profile.photos!.first}')
                    : null,
                child: profile?.photos?.isNotEmpty == true
                    ? null
                    : Text(
                        name[0].toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: VlvtColors.gold,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  child: Center(
                    child: Text(
                      unreadCount > 9 ? '9+' : unreadCount.toString(),
                      style: const TextStyle(
                        color: VlvtColors.textOnGold,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$name, $age',
                style: VlvtTextStyles.bodyLarge.copyWith(
                  fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
                  color: VlvtColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VlvtTextStyles.bodySmall.copyWith(
                color: lastMessage != null ? VlvtColors.textPrimary : VlvtColors.textSecondary,
                fontStyle: lastMessage != null ? FontStyle.normal : FontStyle.italic,
                fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
            if (lastMessage != null)
              Text(
                formatTimestamp(lastMessage.timestamp),
                style: VlvtTextStyles.labelSmall.copyWith(
                  color: VlvtColors.textMuted,
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatTimestamp(lastMessage?.timestamp ?? match.createdAt),
              style: VlvtTextStyles.labelSmall.copyWith(
                color: VlvtColors.textMuted,
              ),
            ),
            if (unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: VlvtColors.gold,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unreadCount > 9 ? '9+' : unreadCount.toString(),
                  style: const TextStyle(
                    color: VlvtColors.textOnGold,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Montserrat',
                  ),
                ),
              ),
          ],
        ),
        onTap: () async {
          await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(match: match),
            ),
          );
          // Always refresh last messages when returning from chat
          if (mounted) {
            _loadData(forceRefresh: true);
          }
        },
        onLongPress: () => _showMatchActions(match),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final userId = authService.userId;

    if (userId == null) {
      return Scaffold(
        backgroundColor: VlvtColors.background,
        appBar: AppBar(
          backgroundColor: VlvtColors.background,
          title: Text('Chats', style: VlvtTextStyles.h2),
        ),
        body: Center(
          child: Text('User not authenticated', style: VlvtTextStyles.bodyMedium),
        ),
      );
    }

    final filteredMatches = _getFilteredAndSortedMatches();

    return Scaffold(
      backgroundColor: VlvtColors.background,
      body: RefreshIndicator(
        color: VlvtColors.gold,
        onRefresh: _handleRefresh,
        child: CustomScrollView(
          slivers: [
            // Collapsible SliverAppBar with elegant title
            SliverAppBar(
              expandedHeight: 100.0,
              floating: true,
              pinned: true,
              backgroundColor: VlvtColors.background,
              flexibleSpace: FlexibleSpaceBar(
                title: _isSearching
                    ? null
                    : Text(
                        'Chats',
                        style: VlvtTextStyles.h2.copyWith(
                          fontFamily: 'PlayfairDisplay',
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                centerTitle: false,
                titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              ),
              actions: [
                if (_isSearching)
                  IconButton(
                    icon: const Icon(Icons.clear, color: VlvtColors.textSecondary),
                    onPressed: () {
                      setState(() {
                        _isSearching = false;
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                  )
                else ...[
                  IconButton(
                    icon: const Icon(Icons.search, color: VlvtColors.gold),
                    onPressed: () {
                      setState(() {
                        _isSearching = true;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.sort, color: VlvtColors.gold),
                    onPressed: _showSortDialog,
                  ),
                ],
              ],
            ),
            // Search bar when searching
            if (_isSearching)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: VlvtInput(
                    controller: _searchController,
                    focusNode: FocusNode()..requestFocus(),
                    hintText: 'Search chats...',
                    blur: false,
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ),
            // Content
            ..._buildSliverBody(filteredMatches, userId),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSliverBody(List<Match> filteredMatches, String userId) {
    // Show loading indicator on initial load
    if (_isLoading && _matches.isEmpty) {
      return [
        const SliverFillRemaining(
          child: Center(child: VlvtLoader()),
        ),
      ];
    }

    // Show error state
    if (_error != null && _matches.isEmpty) {
      return [
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 80,
                  color: VlvtColors.crimson,
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading chats',
                  style: VlvtTextStyles.h2.copyWith(
                    color: VlvtColors.crimson,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _error!,
                    style: VlvtTextStyles.bodyMedium.copyWith(
                      color: VlvtColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                VlvtButton.primary(
                  label: 'Retry',
                  onPressed: () => _loadData(forceRefresh: true),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    // Show empty state (no matches at all)
    if (_matches.isEmpty) {
      return [
        SliverFillRemaining(
          child: ChatsEmptyState.noChats(
            onGoToDiscovery: () {
              // Navigate to discovery tab
              final mainScreenState = context.findAncestorStateOfType<State>();
              if (mainScreenState != null && mainScreenState.mounted) {
                // Try to find MainScreenState and switch tab
              }
            },
          ),
        ),
      ];
    }

    // Show "no results" state (filtered results are empty)
    if (filteredMatches.isEmpty) {
      return [
        SliverFillRemaining(
          child: ChatsEmptyState.noSearchResults(),
        ),
      ];
    }

    // Show matches list with sliver
    return [
      if (_lastUpdated != null)
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: VlvtColors.surfaceElevated,
            child: Center(
              child: Text(
                'Updated ${_getRelativeTime(_lastUpdated!)}',
                style: VlvtTextStyles.labelSmall.copyWith(color: VlvtColors.textMuted),
              ),
            ),
          ),
        ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final match = filteredMatches[index];
            return _buildMatchItem(match, userId);
          },
          childCount: filteredMatches.length,
        ),
      ),
    ];
  }

  String _getRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 60) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return '${difference.inDays}d ago';
    }
  }
}

/// Empty state widget for ChatsScreen
class ChatsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? buttonLabel;
  final VoidCallback? onButtonPressed;

  const ChatsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.buttonLabel,
    this.onButtonPressed,
  });

  factory ChatsEmptyState.noChats({VoidCallback? onGoToDiscovery}) {
    return ChatsEmptyState(
      icon: Icons.chat_bubble_outline,
      title: 'No Chats Yet',
      subtitle: 'Start swiping to find matches and begin chatting!',
      buttonLabel: 'Go to Discovery',
      onButtonPressed: onGoToDiscovery,
    );
  }

  factory ChatsEmptyState.noSearchResults() {
    return const ChatsEmptyState(
      icon: Icons.search_off,
      title: 'No Results',
      subtitle: 'No chats match your search. Try a different name.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 80,
              color: VlvtColors.textMuted,
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: VlvtTextStyles.h2.copyWith(
                color: VlvtColors.gold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: VlvtTextStyles.bodyMedium.copyWith(
                color: VlvtColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (buttonLabel != null && onButtonPressed != null) ...[
              const SizedBox(height: 24),
              VlvtButton.primary(
                label: buttonLabel!,
                onPressed: onButtonPressed,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
