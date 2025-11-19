import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import '../widgets/empty_state_widget.dart';
import '../widgets/loading_skeleton.dart';
import 'chat_screen.dart';

enum SortOption { recentActivity, newestMatches, nameAZ }

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
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
  SortOption _sortOption = SortOption.recentActivity;
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
      case SortOption.recentActivity:
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
      case SortOption.newestMatches:
        // Sort by match creation date (newest first)
        filteredMatches.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case SortOption.nameAZ:
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
        title: const Text('Sort by'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<SortOption>(
              title: const Text('Recent Activity'),
              value: SortOption.recentActivity,
              groupValue: _sortOption,
              onChanged: (value) {
                setState(() {
                  _sortOption = value!;
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile<SortOption>(
              title: const Text('Newest Matches'),
              value: SortOption.newestMatches,
              groupValue: _sortOption,
              onChanged: (value) {
                setState(() {
                  _sortOption = value!;
                });
                Navigator.pop(context);
              },
            ),
            RadioListTile<SortOption>(
              title: const Text('Name (A-Z)'),
              value: SortOption.nameAZ,
              groupValue: _sortOption,
              onChanged: (value) {
                setState(() {
                  _sortOption = value!;
                });
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
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
        title: const Text('Unmatch'),
        content: Text('Are you sure you want to unmatch with $name? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Unmatch'),
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
            backgroundColor: Colors.red,
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
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        await _handleUnmatch(match);
        return false; // We handle removal ourselves
      },
      child: ListTile(
        leading: Stack(
          children: [
            Hero(
              tag: 'profile_${match.otherUser.userId}',
              child: CircleAvatar(
                backgroundColor: Colors.deepPurple,
                child: Text(
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
                    color: Colors.red,
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
                        color: Colors.white,
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
                style: TextStyle(
                  fontWeight: unreadCount > 0 ? FontWeight.bold : FontWeight.normal,
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
              style: TextStyle(
                color: lastMessage != null ? Colors.black87 : Colors.grey,
                fontStyle: lastMessage != null ? FontStyle.normal : FontStyle.italic,
                fontWeight: unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
            if (lastMessage != null)
              Text(
                formatTimestamp(lastMessage.timestamp),
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatTimestamp(match.createdAt),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            if (unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.deepPurple,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  unreadCount > 9 ? '9+' : unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(match: match),
            ),
          );
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
        appBar: AppBar(
          title: const Text('Matches'),
        ),
        body: const Center(
          child: Text('User not authenticated'),
        ),
      );
    }

    final filteredMatches = _getFilteredAndSortedMatches();

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search matches...',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                  });
                },
              )
            : const Text('Matches'),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.clear),
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
              icon: const Icon(Icons.search),
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.sort),
              onPressed: _showSortDialog,
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: _buildBody(filteredMatches, userId),
      ),
    );
  }

  Widget _buildBody(List<Match> filteredMatches, String userId) {
    // Show loading indicator on initial load
    if (_isLoading && _matches.isEmpty) {
      return const MatchListSkeleton();
    }

    // Show error state
    if (_error != null && _matches.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 80,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading matches',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _loadData(forceRefresh: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Show empty state (no matches at all)
    if (_matches.isEmpty) {
      return MatchesEmptyState.noMatches(
        onGoToDiscovery: () {
          // Navigate to discovery screen - switch to first tab
          final tabController = DefaultTabController.of(context);
          tabController.animateTo(0);
        },
      );
    }

    // Show "no results" state (filtered results are empty)
    if (filteredMatches.isEmpty) {
      return MatchesEmptyState.noSearchResults();
    }

    // Show matches list
    return Column(
      children: [
        if (_lastUpdated != null)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            color: Colors.grey[200],
            child: Center(
              child: Text(
                'Updated ${_getRelativeTime(_lastUpdated!)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: filteredMatches.length,
            itemBuilder: (context, index) {
              final match = filteredMatches[index];
              return _buildMatchItem(match, userId);
            },
          ),
        ),
      ],
    );
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
