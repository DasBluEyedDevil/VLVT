import 'package:flutter/material.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  int _currentProfileIndex = 0;
  
  // Stub profile data
  final List<Map<String, dynamic>> _profiles = [
    {
      'name': 'Alex',
      'age': 28,
      'bio': 'Love hiking and outdoor adventures',
      'photo': Icons.person,
    },
    {
      'name': 'Sam',
      'age': 26,
      'bio': 'Foodie and travel enthusiast',
      'photo': Icons.person,
    },
    {
      'name': 'Jordan',
      'age': 30,
      'bio': 'Book lover and coffee addict',
      'photo': Icons.person,
    },
  ];

  void _onLike() {
    setState(() {
      if (_currentProfileIndex < _profiles.length - 1) {
        _currentProfileIndex++;
      } else {
        _showEndOfProfilesMessage();
      }
    });
  }

  void _onPass() {
    setState(() {
      if (_currentProfileIndex < _profiles.length - 1) {
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
    if (_currentProfileIndex >= _profiles.length) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Discovery'),
        ),
        body: const Center(
          child: Text(
            'No more profiles available',
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
    }

    final profile = _profiles[_currentProfileIndex];

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
                        Icon(
                          profile['photo'] as IconData,
                          size: 120,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '${profile['name']}, ${profile['age']}',
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
                            profile['bio'] as String,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
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
