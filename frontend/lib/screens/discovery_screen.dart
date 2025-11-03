import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/profile_api_service.dart';
import '../services/auth_service.dart';
import '../services/chat_api_service.dart';
import '../models/profile.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  int _currentProfileIndex = 0;
  List<Profile>? _profiles;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profileService = context.read<ProfileApiService>();
      final profiles = await profileService.getDiscoveryProfiles();
      setState(() {
        _profiles = profiles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load profiles: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _onLike() async {
    if (_profiles == null || _currentProfileIndex >= _profiles!.length) {
      return;
    }

    final profile = _profiles![_currentProfileIndex];
    
    try {
      // Get services
      final authService = context.read<AuthService>();
      final chatService = context.read<ChatApiService>();
      final currentUserId = authService.userId;
      
      if (currentUserId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User not authenticated')),
          );
        }
        return;
      }
      
      // Create match
      final result = await chatService.createMatch(currentUserId, profile.userId);
      final alreadyExists = result['alreadyExists'] as bool;
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              alreadyExists 
                ? 'You already matched with ${profile.name ?? "user"}!'
                : 'Matched with ${profile.name ?? "user"}!'
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create match: $e')),
        );
      }
    }
    
    // Move to next profile
    setState(() {
      if (_currentProfileIndex < _profiles!.length - 1) {
        _currentProfileIndex++;
      } else {
        _showEndOfProfilesMessage();
      }
    });
  }

  void _onPass() {
    setState(() {
      if (_profiles != null && _currentProfileIndex < _profiles!.length - 1) {
        _currentProfileIndex++;
      } else {
        _showEndOfProfilesMessage();
      }
    });
  }

  void _showEndOfProfilesMessage() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No more profiles for now!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Discovery'),
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
        ),
        body: Center(
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
                onPressed: _loadProfiles,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_profiles == null || _profiles!.isEmpty || _currentProfileIndex >= _profiles!.length) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Discovery'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'No more profiles available',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _currentProfileIndex = 0;
                  });
                  _loadProfiles();
                },
                child: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    final profile = _profiles![_currentProfileIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discovery'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Container(
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
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
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            profile.bio ?? 'No bio available',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (profile.interests != null && profile.interests!.isNotEmpty) ...[
                          const SizedBox(height: 16),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
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
      ),
    );
  }
}
