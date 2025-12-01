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
import '../models/match.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../utils/date_utils.dart';
import '../widgets/user_action_sheet.dart';
import '../widgets/premium_gate_dialog.dart';
import '../widgets/vlvt_input.dart';
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
  final bool _isSending = false;
  String? _errorMessage;
  Profile? _otherUserProfile;
  String? _otherUserId;
  Timer? _typingTimer;
  Timer? _typingIndicatorTimer;
  bool _isTyping = false;
  bool _otherUserTyping = false;
  bool _isRefreshing = false;
  bool _isOtherUserOnline = false;

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
    if (state == AppLifecycleState.resumed) {
      if (!socketService.isConnected) {
        socketService.connect();
      }
      Future.delayed(const Duration(seconds: 1), () async {
        if (socketService.isConnected) {
          final queueService = context.read<MessageQueueService>();
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
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animated: true));
      }
      _markMessagesAsRead();
    });
    _readReceiptSubscription = socketService.onMessagesRead.listen((data) {
      if (!mounted || data['matchId'] != _match?.id) return;
      final messageIds = (data['messageIds'] as List?)?.cast<String>() ?? [];
      setState(() {
        _messages = _messages?.map((m) {
          return messageIds.contains(m.id) ? m.copyWith(status: MessageStatus.read) : m;
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

  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    return _scrollController.position.maxScrollExtent - _scrollController.position.pixels < 100.0;
  }

  void _scrollToBottom({bool animated = false}) {
    if (!_scrollController.hasClients) return;
    final extent = _scrollController.position.maxScrollExtent;
    if (animated) {
      _scrollController.animateTo(extent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _scrollController.jumpTo(extent);
    }
  }

  Future<void> _loadData() async {
    if (_match == null) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final authService = context.read<AuthService>();
      final currentUserId = authService.userId;
      if (currentUserId == null) throw Exception('User not authenticated');

      final otherUserId = _match!.getOtherUserId(currentUserId);
      _otherUserId = otherUserId;

      final results = await Future.wait([
        context.read<ChatApiService>().getMessages(_match!.id),
        context.read<ProfileApiService>().getProfile(otherUserId),
      ]);

      setState(() {
        _messages = results[0] as List<Message>;
        _otherUserProfile = results[1] as Profile;
      });

      final socketService = context.read<SocketService>();
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
      final messages = await context.read<ChatApiService>().getMessages(_match!.id);
      if (mounted) setState(() => _messages = messages);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to refresh: $e')));
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || text.length > _maxCharacters || _match == null) return;

    final subscriptionService = context.read<SubscriptionService>();
    if (!subscriptionService.canSendMessage()) {
      if (mounted) PremiumGateDialog.showMessagesLimitReached(context);
      return;
    }

    final authService = context.read<AuthService>();
    final currentUserId = authService.userId;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not authenticated')));
      return;
    }

    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final socketService = context.read<SocketService>();

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animated: true));

    if (!socketService.isConnected) {
      final queueService = context.read<MessageQueueService>();
      await queueService.enqueue(QueuedMessage(
        tempId: tempId,
        matchId: _match!.id,
        text: text,
        timestamp: DateTime.now(),
      ));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Message queued. Will send when connected.'),
        backgroundColor: Colors.orange,
      ));
      socketService.connect();
      return;
    }

    try {
      final sentMessage = await socketService.sendMessage(matchId: _match!.id, text: text, tempId: tempId);
      if (sentMessage == null) throw Exception('Failed to send message');
      await subscriptionService.useMessage();
      if (mounted) {
        setState(() {
          _messages = _messages!.where((m) => m.id != tempId).toList()..add(sentMessage);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages = _messages!.map((m) => m.id == tempId ? m.copyWith(status: MessageStatus.failed, error: e.toString()) : m).toList();
        });
      }
    }
  }

  Future<void> _retryMessage(Message failedMessage) async {
    final socketService = context.read<SocketService>();
    setState(() {
      _messages = _messages!.map((m) {
        return m.id == failedMessage.id ? m.copyWith(status: MessageStatus.sending, error: null) : m;
      }).toList();
    });

    try {
      final sentMessage = await socketService.sendMessage(matchId: _match!.id, text: failedMessage.text, tempId: failedMessage.id);
      if (sentMessage == null) throw Exception('Failed to send message');
      if (mounted) {
        setState(() {
          _messages = _messages!.where((m) => m.id != failedMessage.id).toList()..add(sentMessage);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animated: true));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages = _messages!.map((m) => m.id == failedMessage.id ? m.copyWith(status: MessageStatus.failed, error: e.toString()) : m).toList();
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => UserActionSheet(
        otherUserProfile: _otherUserProfile!,
        match: _match!,
        onActionComplete: () => Navigator.of(context).pop(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(_errorMessage!, style: TextStyle(color: VlvtColors.error)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _fetchMatchThenLoadData, child: const Text('Retry')),
        ])),
      );
    }

    final authService = context.watch<AuthService>();
    final subscriptionService = context.watch<SubscriptionService>();
    final currentUserId = authService.userId;
    final messagesRemaining = subscriptionService.getMessagesRemaining();
    final showMessagesCounter = subscriptionService.isDemoMode;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            if (_otherUserProfile?.photos?.isNotEmpty == true)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Hero(
                  tag: 'profile_${_otherUserId!}',
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: CachedNetworkImageProvider(
                      _otherUserProfile!.photos!.first.startsWith('http')
                          ? _otherUserProfile!.photos!.first
                          : '${context.read<ProfileApiService>().baseUrl}${_otherUserProfile!.photos!.first}',
                    ),
                  ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: messagesRemaining > 0 ? VlvtColors.success.withValues(alpha: 0.1) : VlvtColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: messagesRemaining > 0 ? VlvtColors.success : VlvtColors.error,
                    ),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chat, size: 16, color: messagesRemaining > 0 ? VlvtColors.success : VlvtColors.error),
                    const SizedBox(width: 4),
                    Text('$messagesRemaining left', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: messagesRemaining > 0 ? VlvtColors.success : VlvtColors.error)),
                  ]),
                ),
              ),
            ),
          if (_otherUserProfile != null && !showMessagesCounter)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text('${_otherUserProfile!.age ?? '?'}', style: const TextStyle(fontSize: 16)),
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
        child: Column(
          children: [
            Expanded(child: _buildMessagesList(currentUserId)),
            _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessagesList(String? currentUserId) {
    if (_messages == null || _messages!.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.chat_bubble_outline, size: 80, color: VlvtColors.textMuted),
        const SizedBox(height: 16),
        Text('No messages yet', style: TextStyle(fontSize: 18, color: VlvtColors.textSecondary)),
        const SizedBox(height: 8),
        Text('Say hi to ${_otherUserProfile?.name ?? 'your match'}!', style: TextStyle(fontSize: 14, color: VlvtColors.textMuted)),
      ]));
    }
    return RefreshIndicator(
      onRefresh: _refreshMessages,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _messages!.length + (_otherUserTyping ? 1 : 0),
        itemBuilder: (context, index) {
          if (_otherUserTyping && index == _messages!.length) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: VlvtColors.typingIndicatorBackground, borderRadius: BorderRadius.circular(20)),
                child: Text('...', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: VlvtColors.typingIndicatorDots, letterSpacing: 2)),
              ),
            );
          }
          final message = _messages![index];
          return _buildMessageBubble(message, message.senderId == currentUserId);
        },
      ),
    );
  }

  Widget _buildMessageBubble(Message message, bool isCurrentUser) {
    final isFailed = message.status == MessageStatus.failed;
    return Align(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (isCurrentUser && isFailed) ...[
            IconButton(icon: const Icon(Icons.refresh, size: 20), color: VlvtColors.error, onPressed: () => _retryMessage(message), tooltip: 'Retry'),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
              decoration: BoxDecoration(
                color: isFailed ? VlvtColors.error.withValues(alpha: 0.1) : (isCurrentUser ? VlvtColors.chatBubbleSent : VlvtColors.chatBubbleReceived),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(message.text, style: TextStyle(fontSize: 16, color: isFailed ? VlvtColors.error : (isCurrentUser ? VlvtColors.chatTextSent : VlvtColors.chatTextReceived))),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(formatTimestamp(message.timestamp), style: TextStyle(fontSize: 11, color: isFailed ? VlvtColors.error.withValues(alpha: 0.8) : (isCurrentUser ? VlvtColors.chatTimestampSent : VlvtColors.chatTimestampReceived))),
                  if (isCurrentUser && !isFailed) ...[const SizedBox(width: 4), _buildMessageStatusIcon(message.status)],
                ]),
                if (isFailed) ...[
                  const SizedBox(height: 4),
                  Text('Failed to send', style: TextStyle(fontSize: 11, color: VlvtColors.error, fontWeight: FontWeight.bold)),
                ],
              ]),
            ),
          ),
          if (isCurrentUser && isFailed) ...[
            const SizedBox(width: 4),
            IconButton(icon: const Icon(Icons.close, size: 20), color: VlvtColors.error, onPressed: () => _deleteFailedMessage(message), tooltip: 'Delete'),
          ],
        ]),
      ),
    );
  }

  Widget _buildMessageStatusIcon(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending: return SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, valueColor: AlwaysStoppedAnimation<Color>(VlvtColors.chatTimestampSent)));
      case MessageStatus.sent: return Icon(Icons.check, size: 14, color: VlvtColors.chatTimestampSent);
      case MessageStatus.delivered: return Icon(Icons.done_all, size: 14, color: VlvtColors.chatTimestampSent);
      case MessageStatus.read: return Icon(Icons.done_all, size: 14, color: VlvtColors.info);
      case MessageStatus.failed: return Icon(Icons.error_outline, size: 14, color: VlvtColors.error);
    }
  }

  Widget _buildMessageInput() {
    final charCount = _messageController.text.length;
    final isOverLimit = charCount > _maxCharacters;
    final showCounter = charCount > _maxCharacters * 0.8;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(color: VlvtColors.surface, boxShadow: [BoxShadow(color: VlvtColors.border.withValues(alpha: 0.1), spreadRadius: 1, blurRadius: 3, offset: const Offset(0, -1))]),
      child: SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (showCounter)
            Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 4),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('$charCount/$_maxCharacters', style: TextStyle(fontSize: 12, color: isOverLimit ? VlvtColors.error : VlvtColors.textSecondary, fontWeight: isOverLimit ? FontWeight.bold : FontWeight.normal)),
              ]),
            ),
          Row(children: [
            Expanded(
              child: VlvtInput(
                controller: _messageController,
                hintText: 'Type a message...',
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _sendMessage(),
                textInputAction: TextInputAction.send,
                blur: false,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _sendMessage,
              icon: _isSending ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send),
              color: VlvtColors.gold,
              iconSize: 28,
            ),
          ]),
        ]),
      ),
    );
  }
}
