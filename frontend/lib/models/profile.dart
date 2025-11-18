class Profile {
  final String userId;
  final String? name;
  final int? age;
  final String? bio;
  final List<String>? photos;
  final List<String>? interests;
  final double? distance; // Distance in kilometers from current user

  Profile({
    required this.userId,
    this.name,
    this.age,
    this.bio,
    this.photos,
    this.interests,
    this.distance,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      userId: json['userId'] as String,
      name: json['name'] as String?,
      age: json['age'] as int?,
      bio: json['bio'] as String?,
      photos: json['photos'] != null
          ? List<String>.from(json['photos'] as List)
          : null,
      interests: json['interests'] != null
          ? List<String>.from(json['interests'] as List)
          : null,
      distance: json['distance'] != null
          ? (json['distance'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'name': name,
      'age': age,
      'bio': bio,
      'photos': photos,
      'interests': interests,
      if (distance != null) 'distance': distance,
    };
  }
}
