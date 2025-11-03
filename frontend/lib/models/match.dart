class Match {
  final String id;
  final String userId1;
  final String userId2;
  final DateTime createdAt;

  Match({
    required this.id,
    required this.userId1,
    required this.userId2,
    required this.createdAt,
  });

  factory Match.fromJson(Map<String, dynamic> json) {
    return Match(
      id: json['id'] as String,
      userId1: json['userId1'] as String,
      userId2: json['userId2'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId1': userId1,
      'userId2': userId2,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Returns the other user's ID given the current user's ID
  String getOtherUserId(String currentUserId) {
    return userId1 == currentUserId ? userId2 : userId1;
  }
}
