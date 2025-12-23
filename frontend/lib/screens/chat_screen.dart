import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/auth_service.dart';
import '../services/chat_api_service.dart';
import '../services/socket_service.dart';
import '../services/profile_api_service.dart';
import '../services/subscription_service.dart';
import '../services/message_queue_service.dart';
import '../services/cache_service.dart';
import '../models/match.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../utils/date_utils.dart';
import '../widgets/user_action_sheet.dart';
import '../widgets/premium_gate_dialog.dart';
import '../widgets/vlvt_input.dart';
import '../widgets/vlvt_button.dart';
import '../widgets/vlvt_loader.dart';
import '../widgets/date_proposal_sheet.dart';
import '../widgets/date_card.dart';
import '../widgets/message_status_indicator.dart';
import '../services/date_proposal_service.dart';
import '../theme/vlvt_colors.dart';

class ChatScreen extends StatefulWidget {
  final Match? match;
  final String? matchId;

  const ChatScreen({super.key, this.match, this.matchId})
      : assert(match != null || matchId != null);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // State
  Match? _match;
  List<Message>? _messages;
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  Profile? _otherUserProfile;
  String? _otherUserId;
  Timer? _typingTimer;
  Timer? _typingIndicatorTimer;
  bool _isTyping = false;
  bool _otherUserTyping = false;
  bool _isRefreshing = false;
  bool _isOtherUserOnline = false;
  bool _isProfileComplete = true;
  String? _profileCompletionMessage;
  List<String> _missingFields = [];

  // Socket.IO stream subscriptions
  StreamSubscription<Message>? _messageSubscription;
  StreamSubscription<Map<String, dynamic>>? _readReceiptSubscription;
  StreamSubscription<Map<String, dynamic>>? _typingSubscription;
  StreamSubscription<UserStatus>? _statusSubscription;

  static const int _maxCharacters = 500;
  static const Duration _typingTimeout = Duration(seconds: 2);
  static const Duration _typingIndicatorTimeout = Duration(seconds: 3);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.match != null) {
      _match = widget.match;
      _loadData();
    } else {
      _fetchMatchThenLoadData();
    }

    _setupSocketListeners();
    _messageController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelSocketListeners();
    _typingTimer?.cancel();
    _typingIndicatorTimer?.cancel();
    _messageController.removeListener(_onTextChanged);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final socketService = context.read<SocketService>();
    final queueService = context.read<MessageQueueService>();
    if (state == AppLifecycleState.resumed) {
      if (!socketService.isConnected) {
        socketService.connect();
      }
      Future.delayed(const Duration(seconds: 1), () async {
        if (socketService.isConnected) {
          await queueService.processQueue(socketService);
        }
      });
    }
  }

  Future<void> _fetchMatchThenLoadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final authService = context.read<AuthService>();
      final chatService = context.read<ChatApiService>();
      final userId = authService.userId;
      if (userId == null) throw Exception("Not authenticated");

      // Inefficiently find the match from the list of all matches
      final matches = await chatService.getMatches(userId);
      final match = matches.firstWhere((m) => m.id == widget.matchId,
          orElse: () => throw Exception("Match not found"));

      setState(() {
        _match = match;
      });

      await _loadData();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Failed to load match details: $e";
      });
    }
  }

  void _setupSocketListeners() {
    final socketService = context.read<SocketService>();
    if (!socketService.isConnected && !socketService.isConnecting) {
      socketService.connect();
    }
    _messageSubscription = socketService.onNewMessage.listen((message) {
      if (!mounted || message.matchId != _match?.id) return;
      final wasNearBottom = _isNearBottom();
      setState(() {
        _messages = [...(_messages ?? []), message];
      });
      if (wasNearBottom) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom(animated: true));
      }
      _markMessagesAsRead();
    });
    _readReceiptSubscription = socketService.onMessagesRead.listen((data) {
      if (!mounted || data['matchId'] != _match?.id) return;
      final messageIds = (data['messageIds'] as List?)?.cast<String>() ?? [];
      setState(() {
        _messages = _messages?.map((m) {
          return messageIds.contains(m.id)
              ? m.copyWith(status: MessageStatus.read)
              : m;
        }).toList();
      });
    });
    _typingSubscription = socketService.onUserTyping.listen((data) {
      if (!mounted || data['matchId'] != _match?.id) return;
      final userId = data['userId'] as String?;
      if (userId == context.read<AuthService>().userId) return;
      final isTyping = data['isTyping'] as bool? ?? false;
      setState(() => _otherUserTyping = isTyping);
      if (isTyping) {
        _typingIndicatorTimer?.cancel();
        _typingIndicatorTimer = Timer(_typingIndicatorTimeout, () {
          if (mounted) setState(() => _otherUserTyping = false);
        });
      }
    });
    _statusSubscription = socketService.onUserStatusChanged.listen((status) {
      if (mounted && status.userId == _otherUserId) {
        setState(() => _isOtherUserOnline = status.isOnline);
      }
    });
  }

  void _cancelSocketListeners() {
    _messageSubscription?.cancel();
    _readReceiptSubscription?.cancel();
    _typingSubscription?.cancel();
    _statusSubscription?.cancel();
  }

  void _onTextChanged() {
    final socketService = context.read<SocketService>();
    if (_messageController.text.trim().isNotEmpty && !_isTyping) {
      setState(() => _isTyping = true);
      socketService.sendTypingIndicator(matchId: _match!.id, isTyping: true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(_typingTimeout, () {
      if (mounted) {
        setState(() => _isTyping = false);
        socketService.sendTypingIndicator(matchId: _match!.id, isTyping: false);
      }
    });
  }

  Future<void> _markMessagesAsRead() async {
    if (_messages == null || _messages!.isEmpty) return;
    final socketService = context.read<SocketService>();
    if (!socketService.isConnected) return;
    try {
      await socketService.markMessagesAsRead(matchId: _match!.id);
    } catch (e) {
      debugPrint('Failed to mark messages as read: $e');
    }
  }

  /// With reverse:true, position 0 = bottom (newest messages)
  /// So "near bottom" means near position 0
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.pixels < 100.0;
  }

  /// With reverse:true, scrolling to "bottom" means scrolling to position 0
  void _scrollToBottom({bool animated = false}) {
    if (!_scrollController.hasClients) return;
    if (animated) {
      _scrollController.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(0);
    }
  }

  Future<void> _loadData() async {
    if (_match == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    // Get services before async gaps
    final authService = context.read<AuthService>();
    final chatApiService = context.read<ChatApiService>();
    final profileApiService = context.read<ProfileApiService>();
    final socketService = context.read<SocketService>();
    final dateProposalService = context.read<DateProposalService>();
    try {
      final currentUserId = authService.userId;
      if (currentUserId == null) throw Exception('User not authenticated');

      final otherUserId = _match!.getOtherUserId(currentUserId);
      _otherUserId = otherUserId;

      // Check profile completion in parallel with loading messages
      final results = await Future.wait([
        chatApiService.getMessages(_match!.id),
        profileApiService.getProfile(otherUserId),
        profileApiService.checkProfileCompletion(),
      ]);

      final profileCompletionResult = results[2] as Map<String, dynamic>;

      setState(() {
        _messages = results[0] as List<Message>;
        _otherUserProfile = results[1] as Profile;
        _isProfileComplete = profileCompletionResult['isComplete'] == true;
        _profileCompletionMessage =
            profileCompletionResult['message'] as String?;
        _missingFields =
            List<String>.from(profileCompletionResult['missingFields'] ?? []);
      });

      // Load date proposals for this match
      await dateProposalService.loadProposals(_match!.id);

      if (socketService.isConnected) {
        final statuses = await socketService.getOnlineStatus([otherUserId]);
        if (statuses.isNotEmpty && mounted) {
          setState(() => _isOtherUserOnline = statuses.first.isOnline);
        }
      }
      _markMessagesAsRead();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      setState(() => _errorMessage = 'Failed to load chat: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshMessages() async {
    if (_isRefreshing || _match == null) return;
    setState(() => _isRefreshing = true);
    try {
      final messages =
          await context.read<ChatApiService>().getMessages(_match!.id);
      if (mounted) setState(() => _messages = messages);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed to refresh: $e')));
      }
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty ||
        text.length > _maxCharacters ||
        _match == null ||
        _isSending) {
      return;
    }

    // Check profile completion before sending
    if (!_isProfileComplete) {
      final scaffoldMessenger = ScaffoldMessenger.of(context);
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(_profileCompletionMessage ??
              'Please complete your profile to start messaging'),
          backgroundColor: VlvtColors.error,
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Complete Profile',
            textColor: Colors.white,
            onPressed: () {
              Navigator.pushNamed(context, '/profile');
            },
          ),
        ),
      );
      return;
    }

    setState(() => _isSending = true);

    // Get services before async gaps
    final subscriptionService = context.read<SubscriptionService>();
    final authService = context.read<AuthService>();
    final socketService = context.read<SocketService>();
    final queueService = context.read<MessageQueueService>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (!subscriptionService.canSendMessage()) {
      if (mounted) {
        setState(() => _isSending = false);
        PremiumGateDialog.showMessagesLimitReached(context);
      }
      return;
    }

    final currentUserId = authService.userId;
    if (currentUserId == null) {
      if (mounted) setState(() => _isSending = false);
      scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('User not authenticated')));
      return;
    }

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    final tempMessage = Message(
      id: tempId,
      matchId: _match!.id,
      senderId: currentUserId,
      text: text,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );

    setState(() {
      _messages = [...(_messages ?? []), tempMessage];
      _messageController.clear();
    });
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scrollToBottom(animated: true));

    // If socket is connecting, wait for it (up to 5 seconds)
    if (!socketService.isConnected && socketService.isConnecting) {
      for (int i = 0; i < 50; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (socketService.isConnected) break;
      }
    }

    // If still not connected (no connection in progress or timed out), queue the message
    if (!socketService.isConnected) {
      await queueService.queueMessage(QueuedMessage(
        id: tempId,
        matchId: _match!.id,
        content: text,
        queuedAt: DateTime.now(),
      ));
      if (mounted) setState(() => _isSending = false);
      scaffoldMessenger.showSnackBar(const SnackBar(
        content: Text('Message queued. Will send when connected.'),
        backgroundColor: Colors.orange,
      ));
      socketService.connect();
      return;
    }

    try {
      final sentMessage = await socketService.sendMessage(
          matchId: _match!.id, text: text, tempId: tempId);
      if (sentMessage == null) throw Exception('Failed to send message');
      await subscriptionService.useMessage();
      if (mounted) {
        setState(() {
          _isSending = false;
          _messages = _messages!.where((m) => m.id != tempId).toList()
            ..add(sentMessage);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _messages = _messages!
              .map((m) => m.id == tempId
                  ? m.copyWith(
                      status: MessageStatus.failed, error: e.toString())
                  : m)
              .toList();
        });
      }
    }
  }

  void _showDateProposalSheet() {
    if (_match == null || _otherUserProfile == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DateProposalSheet(
        matchName: _otherUserProfile!.name ?? 'them',
        onSubmit: ({
          required String placeName,
          required DateTime proposedDate,
          required String proposedTime,
          String? placeAddress,
          String? note,
        }) async {
          Navigator.pop(context);

          final dateProposalService = context.read<DateProposalService>();
          final scaffoldMessenger = ScaffoldMessenger.of(context);

          final result = await dateProposalService.createProposal(
            matchId: _match!.id,
            placeName: placeName,
            proposedDate: proposedDate,
            proposedTime: proposedTime,
            placeAddress: placeAddress,
            note: note,
          );

          if (result['success'] == true) {
            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text('Date proposal sent!'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            scaffoldMessenger.showSnackBar(
              SnackBar(
                content: Text(result['error'] ?? 'Failed to send proposal'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _retryMessage(Message failedMessage) async {
    final socketService = context.read<SocketService>();
    setState(() {
      _messages = _messages!.map((m) {
        return m.id == failedMessage.id
            ? m.copyWith(status: MessageStatus.sending, error: null)
            : m;
      }).toList();
    });

    try {
      final sentMessage = await socketService.sendMessage(
          matchId: _match!.id,
          text: failedMessage.text,
          tempId: failedMessage.id);
      if (sentMessage == null) throw Exception('Failed to send message');
      if (mounted) {
        setState(() {
          _messages = _messages!.where((m) => m.id != failedMessage.id).toList()
            ..add(sentMessage);
        });
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _scrollToBottom(animated: true));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages = _messages!
              .map((m) => m.id == failedMessage.id
                  ? m.copyWith(
                      status: MessageStatus.failed, error: e.toString())
                  : m)
              .toList();
        });
      }
    }
  }

  void _deleteFailedMessage(Message message) {
    setState(() {
      _messages = _messages!.where((m) => m.id != message.id).toList();
    });
  }

  void _showUserActionSheet() {
    if (_otherUserProfile == null || _match == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => UserActionSheet(
        otherUserProfile: _otherUserProfile!,
        match: _match!,
        onActionComplete: () {
          // Invalidate caches so matches list refreshes properly
          final authService = context.read<AuthService>();
          final cacheService = context.read<CacheService>();
          final userId = authService.userId;
          if (userId != null) {
            cacheService.invalidateMatches(userId);
          }
          cacheService.invalidateMessages(_match!.id);
          cacheService.invalidateLastMessage(_match!.id);

          // Navigate back to matches list, signaling that data changed
          Navigator.of(context).pop(true);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
          appBar: AppBar(), body: const Center(child: VlvtLoader()));
    }
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_errorMessage!, style: TextStyle(color: VlvtColors.error)),
          const SizedBox(height: 16),
          VlvtButton.primary(
              label: 'Retry', onPressed: _fetchMatchThenLoadData),
        ])),
      );
    }

    final authService = context.watch<AuthService>();
    final subscriptionService = context.watch<SubscriptionService>();
    final currentUserId = authService.userId;
    final messagesRemaining = subscriptionService.getMessagesRemaining();
    final showMessagesCounter = subscriptionService.isFreeUser;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            if (_otherUserProfile?.photos?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Stack(
                  children: [
                    Hero(
                      tag: 'avatar_$_otherUserId',
                      child: CircleAvatar(
                        radius: 18,
                        backgroundImage: CachedNetworkImageProvider(
                          _otherUserProfile!.photos!.first.startsWith('http')
                              ? _otherUserProfile!.photos!.first
                              : '${context.read<ProfileApiService>().baseUrl}${_otherUserProfile!.photos!.first}',
                        ),
                      ),
                    ),
                    // Online status indicator
                    if (_isOtherUserOnline)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: VlvtColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: VlvtColors.background,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(child: Text(_otherUserProfile?.name ?? 'Chat')),
          ],
        ),
        actions: [
          if (showMessagesCounter)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: messagesRemaining > 0
                        ? VlvtColors.success.withValues(alpha: 0.1)
                        : VlvtColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: messagesRemaining > 0
                          ? VlvtColors.success
                          : VlvtColors.error,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chat,
                        size: 16,
                        color: messagesRemaining > 0
                            ? VlvtColors.success
                            : VlvtColors.error),
                    const SizedBox(width: 4),
                    Text('$messagesRemaining left',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: messagesRemaining > 0
                                ? VlvtColors.success
                                : VlvtColors.error)),
                  ]),
                ),
              ),
            ),
          if (_otherUserProfile != null && !showMessagesCounter)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text('${_otherUserProfile!.age ?? '?'}',
                    style: const TextStyle(fontSize: 16)),
              ),
            ),
          if (_otherUserProfile != null)
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: _showUserActionSheet,
              tooltip: 'More options',
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Consumer<DateProposalService>(
          builder: (context, dateProposalService, child) {
            final proposals = _match != null
                ? dateProposalService.getProposalsForMatch(_match!.id)
                : <DateProposal>[];
            // Show active proposals (pending or accepted)
            final activeProposals = proposals
                .where((p) => p.status == 'pending' || p.status == 'accepted')
                .toList();

            return Column(
              children: [
                // Date proposals card at top
                if (activeProposals.isNotEmpty)
                  _buildDateProposalCard(activeProposals.first, currentUserId),
                // Profile completion banner
                if (!_isProfileComplete) _buildProfileCompletionBanner(),
                Expanded(child: _buildMessagesList(currentUserId)),
                _buildMessageInput(),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDateProposalCard(DateProposal proposal, String? currentUserId) {
    return DateCard(
      proposal: proposal,
      currentUserId: currentUserId ?? '',
      onAccept: () => _respondToProposal(proposal, 'accepted'),
      onDecline: () => _respondToProposal(proposal, 'declined'),
      onConfirm: () => _confirmDate(proposal),
      onCancel: () => _cancelProposal(proposal),
    );
  }

  Widget _buildProfileCompletionBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: VlvtColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VlvtColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: VlvtColors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _profileCompletionMessage ??
                      'Please complete your profile to start messaging',
                  style: TextStyle(
                    fontSize: 14,
                    color: VlvtColors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (_missingFields.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Missing: ${_missingFields.join(", ")}',
                    style: TextStyle(
                      fontSize: 12,
                      color: VlvtColors.error.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, '/profile'),
            child: Text(
              'Complete',
              style: TextStyle(
                color: VlvtColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _respondToProposal(
      DateProposal proposal, String response) async {
    final dateProposalService = context.read<DateProposalService>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final result = await dateProposalService.respondToProposal(
      proposalId: proposal.id,
      matchId: proposal.matchId,
      response: response,
    );

    if (result['success'] == true) {
      scaffoldMessenger.showSnackBar(SnackBar(
        content:
            Text(response == 'accepted' ? 'Date accepted!' : 'Date declined'),
        backgroundColor: response == 'accepted' ? VlvtColors.success : null,
      ));
    } else {
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(result['error'] ?? 'Failed to respond'),
        backgroundColor: VlvtColors.error,
      ));
    }
  }

  Future<void> _confirmDate(DateProposal proposal) async {
    final dateProposalService = context.read<DateProposalService>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final result = await dateProposalService.confirmDate(
      proposalId: proposal.id,
      matchId: proposal.matchId,
    );

    if (result['success'] == true) {
      final message = result['completed'] == true
          ? 'Date confirmed! ${result['ticketAwarded'] == true ? 'You earned a Golden Ticket!' : ''}'
          : 'Confirmed! Waiting for ${_otherUserProfile?.name ?? 'them'} to confirm.';
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: VlvtColors.success,
      ));
    } else {
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(result['error'] ?? 'Failed to confirm'),
        backgroundColor: VlvtColors.error,
      ));
    }
  }

  Future<void> _cancelProposal(DateProposal proposal) async {
    final dateProposalService = context.read<DateProposalService>();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    final result = await dateProposalService.cancelProposal(
      proposalId: proposal.id,
      matchId: proposal.matchId,
    );

    if (result['success'] == true) {
      scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Date proposal cancelled')));
    } else {
      scaffoldMessenger.showSnackBar(SnackBar(
        content: Text(result['error'] ?? 'Failed to cancel'),
        backgroundColor: VlvtColors.error,
      ));
    }
  }

  Widget _buildMessagesList(String? currentUserId) {
    if (_messages == null || _messages!.isEmpty) {
      return Center(
          child: SingleChildScrollView(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.chat_bubble_outline, size: 64, color: VlvtColors.textMuted),
        const SizedBox(height: 12),
        Text('No messages yet',
            style: TextStyle(fontSize: 16, color: VlvtColors.textSecondary)),
        const SizedBox(height: 4),
        Text('Say hi to ${_otherUserProfile?.name ?? 'your match'}!',
            style: TextStyle(fontSize: 13, color: VlvtColors.textMuted)),
      ])));
    }

    // Build items list: typing indicator (if any) + messages in REVERSE order
    // With reverse:true, index 0 is at the bottom of the screen
    // So we need: [typing_indicator (if any), newest_message, ..., oldest_message]
    final itemCount = _messages!.length + (_otherUserTyping ? 1 : 0);

    return RefreshIndicator(
      onRefresh: _refreshMessages,
      child: ListView.builder(
        controller: _scrollController,
        reverse: true, // CRITICAL: newest at bottom, scroll position 0 = bottom
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          // With reverse:true, index 0 is the bottom-most item (newest)
          // Typing indicator should be at the very bottom (index 0 when typing)
          if (_otherUserTyping && index == 0) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin:
                    const EdgeInsets.only(top: 8), // top margin since reversed
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                    color: VlvtColors.typingIndicatorBackground,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('...',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: VlvtColors.typingIndicatorDots,
                        letterSpacing: 2)),
              ),
            );
          }

          // Adjust index to account for typing indicator
          final messageIndex = _otherUserTyping ? index - 1 : index;
          // Reverse: index 0 (or 1 if typing) = newest message = last in _messages
          final reversedIndex = _messages!.length - 1 - messageIndex;
          final message = _messages![reversedIndex];
          final isCurrentUser = message.senderId == currentUserId;

          // Message grouping logic (check the message ABOVE in visual order = BELOW in list order)
          // In reversed list, "previous" visually is the next index
          final nextMessageIndex = reversedIndex + 1;
          final previousMessageVisually = nextMessageIndex < _messages!.length
              ? _messages![nextMessageIndex]
              : null;
          final isSameSender =
              previousMessageVisually?.senderId == message.senderId;
          final isCloseInTime = previousMessageVisually != null &&
              message.timestamp
                      .difference(previousMessageVisually.timestamp)
                      .inMinutes
                      .abs() <
                  2;
          final isGrouped = isSameSender && isCloseInTime;

          return _buildMessageBubble(message, isCurrentUser,
              isGrouped: isGrouped);
        },
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isCurrentUser,
      {bool isGrouped = false}) {
    final isFailed = message.status == MessageStatus.failed;
    // Tighter spacing for grouped messages (same sender, close in time)
    // With reverse:true, we use top margin instead of bottom
    final topMargin = isGrouped ? 4.0 : 12.0;

    // Differential border radius for modern chat bubble style
    // The corner near the "tail" (bottom-right for sender, bottom-left for receiver) is smaller
    final borderRadius = isCurrentUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(20),
            bottomRight: Radius.circular(6), // Tail corner
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomLeft: Radius.circular(6), // Tail corner
            bottomRight: Radius.circular(20),
          );

    return Align(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(top: topMargin),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isCurrentUser && isFailed) ...[
                IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    color: VlvtColors.error,
                    onPressed: () => _retryMessage(message),
                    tooltip: 'Retry'),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7),
                  decoration: BoxDecoration(
                    color: isFailed
                        ? VlvtColors.error.withValues(alpha: 0.1)
                        : (isCurrentUser
                            ? VlvtColors.chatBubbleSent
                            : VlvtColors.chatBubbleReceived),
                    borderRadius: borderRadius,
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(message.text,
                            style: TextStyle(
                                fontSize: 16,
                                color: isFailed
                                    ? VlvtColors.error
                                    : (isCurrentUser
                                        ? VlvtColors.chatTextSent
                                        : VlvtColors.chatTextReceived))),
                        const SizedBox(height: 4),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(formatTimestamp(message.timestamp),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: isFailed
                                      ? VlvtColors.error.withValues(alpha: 0.8)
                                      : (isCurrentUser
                                          ? VlvtColors.chatTimestampSent
                                          : VlvtColors.chatTimestampReceived))),
                          if (isCurrentUser && !isFailed) ...[
                            const SizedBox(width: 4),
                            _buildMessageStatusIcon(message.status)
                          ],
                        ]),
                        if (isFailed) ...[
                          const SizedBox(height: 4),
                          Text('Failed to send',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: VlvtColors.error,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ]),
                ),
              ),
              if (isCurrentUser && isFailed) ...[
                const SizedBox(width: 4),
                IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: VlvtColors.error,
                    onPressed: () => _deleteFailedMessage(message),
                    tooltip: 'Delete'),
              ],
            ]),
      ),
    );
  }

  Widget _buildMessageStatusIcon(MessageStatus status) {
    // Use the new MessageStatusIndicator widget
    return MessageStatusIndicator(
      status: status,
      size: 14,
    );
  }

  Widget _buildMessageInput() {
    final charCount = _messageController.text.length;
    final isOverLimit = charCount > _maxCharacters;
    final showCounter = charCount > _maxCharacters * 0.8;
    final isDisabled = !_isProfileComplete;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: VlvtColors.surface, boxShadow: [
        BoxShadow(
            color: VlvtColors.border.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -1))
      ]),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (showCounter)
            Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('$charCount/$_maxCharacters',
                    style: TextStyle(
                        fontSize: 12,
                        color: isOverLimit
                            ? VlvtColors.error
                            : VlvtColors.textSecondary,
                        fontWeight:
                            isOverLimit ? FontWeight.bold : FontWeight.normal)),
              ]),
            ),
          Row(children: [
            // Calendar button for date proposals
            IconButton(
              onPressed: _showDateProposalSheet,
              icon: const Icon(Icons.calendar_today),
              color: VlvtColors.gold,
              iconSize: 24,
              tooltip: 'Propose a Date',
            ),
            Expanded(
              child: VlvtInput(
                controller: _messageController,
                hintText: isDisabled
                    ? 'Complete your profile to message'
                    : 'Type a message...',
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
                textInputAction: TextInputAction.send,
                blur: false,
                enabled: !isDisabled,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: isDisabled ? null : _sendMessage,
              icon: _isSending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              color: isDisabled ? VlvtColors.textMuted : VlvtColors.gold,
              iconSize: 28,
            ),
          ]),
        ]),
      ),
    );
  }
}
