import 'package:flutter/material.dart';

class MatchesScreen extends StatelessWidget {
  const MatchesScreen({super.key});

  // Stub matches data
  static final List<Map<String, dynamic>> _matches = [
    {
      'name': 'Alex',
      'age': 28,
      'lastMessage': 'Hey! How are you?',
      'timestamp': '2h ago',
    },
    {
      'name': 'Sam',
      'age': 26,
      'lastMessage': 'Want to grab coffee?',
      'timestamp': '5h ago',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Matches'),
      ),
      body: _matches.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 100,
                    color: Colors.grey,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No matches yet',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Keep swiping to find your match!',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _matches.length,
              itemBuilder: (context, index) {
                final match = _matches[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.deepPurple,
                    child: Text(
                      match['name'][0],
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  title: Text(
                    '${match['name']}, ${match['age']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(match['lastMessage']),
                  trailing: Text(
                    match['timestamp'],
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                  onTap: () {
                    // Navigate to chat screen (stub)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Chat with ${match['name']}'),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
