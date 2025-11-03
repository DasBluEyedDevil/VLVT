import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/chat_api_service.dart';
import '../services/profile_api_service.dart';
import '../models/match.dart';
import '../models/message.dart';
import '../models/profile.dart';
import '../utils/date_utils.dart';

class ChatScreen extends StatefulWidget {
  final Match match;

  const ChatScreen({super.key, required this.match});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Message>? _messages;
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorMessage;
  Profile? _otherUserProfile;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = context.read<AuthService>();
      final chatService = context.read<ChatApiService>();
      final profileService = context.read<ProfileApiService>();
      final currentUserId = authService.userId;

      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }

      // Get the other user's ID
      final otherUserId = widget.match.getOtherUserId(currentUserId);

      // Load messages and other user's profile in parallel
      final results = await Future.wait([
        chatService.getMessages(widget.match.id),
        profileService.getProfile(otherUserId),
      ]);

      setState(() {
        _messages = results[0] as List<Message>;
        _otherUserProfile = results[1] as Profile;
        _isLoading = false;
      });

      // Scroll to bottom after messages are loaded
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load chat: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final authService = context.read<AuthService>();
    final chatService = context.read<ChatApiService>();
    final currentUserId = authService.userId;

    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final newMessage = await chatService.sendMessage(
        widget.match.id,
        currentUserId,
        text,
      );

      setState(() {
        _messages = [...(_messages ?? []), newMessage];
        _messageController.clear();
        _isSending = false;
      });

      // Scroll to bottom after sending
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() {
        _isSending = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final currentUserId = authService.userId;

    return Scaffold(
      appBar: AppBar(
        title: Text(_otherUserProfile?.name ?? 'Chat'),
        actions: [
          if (_otherUserProfile != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_otherUserProfile!.age ?? '?'}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: _buildMessagesList(currentUserId),
          ),
          // Message input
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessagesList(String? currentUserId) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              style: const TextStyle(fontSize: 16, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_messages == null || _messages!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Say hi to ${_otherUserProfile?.name ?? 'your match'}!',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages!.length,
      itemBuilder: (context, index) {
        final message = _messages![index];
        final isCurrentUser = message.senderId == currentUserId;

        return Align(
          alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            decoration: BoxDecoration(
              color: isCurrentUser ? Colors.deepPurple : Colors.grey[300],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 16,
                    color: isCurrentUser ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatTimestamp(message.timestamp),
                  style: TextStyle(
                    fontSize: 11,
                    color: isCurrentUser ? Colors.white70 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                maxLines: null,
                textCapitalization: TextCapitalization.sentences,
                enabled: !_isSending,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _isSending ? null : _sendMessage,
              icon: _isSending
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              color: Colors.deepPurple,
              iconSize: 28,
            ),
          ],
        ),
      ),
    );
  }


}
