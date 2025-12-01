/// HeroTags - Centralized hero tag generation for consistent animations
///
/// This utility ensures hero animations work correctly by preventing
/// tag collisions between different screens that might show the same profile.
///
/// Usage:
/// ```dart
/// Hero(
///   tag: HeroTags.discoveryProfile(userId),
///   child: ProfileImage(...),
/// )
/// ```
class HeroTags {
  HeroTags._();

  /// Discovery screen profile images
  /// Use when showing a profile card in the discovery swipe view
  static String discoveryProfile(String userId) => 'discovery_$userId';

  /// Match list profile images
  /// Use when showing a match in the matches list
  static String matchListProfile(String matchId, String userId) =>
      'match_list_${matchId}_$userId';

  /// Chat screen profile images
  /// Use when showing the other user's profile in chat
  static String chatProfile(String userId) => 'chat_$userId';

  /// Profile detail screen
  /// Use when navigating to a full profile view
  static String profileDetail(String userId) => 'profile_detail_$userId';

  /// User's own profile (settings/edit screens)
  static String ownProfile(String userId) => 'own_profile_$userId';

  /// Photo gallery viewer
  /// Use when opening a photo in full screen
  static String photoGallery(String userId, int photoIndex) =>
      'gallery_${userId}_$photoIndex';

  /// Match overlay (for match celebration animation)
  static String matchOverlay(String matchId) => 'match_overlay_$matchId';
}
