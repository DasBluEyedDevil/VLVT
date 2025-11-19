import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class DiscoveryFilters {
  final int minAge;
  final int maxAge;
  final double maxDistance; // in km
  final List<String> selectedInterests;

  DiscoveryFilters({
    this.minAge = 18,
    this.maxAge = 99,
    this.maxDistance = 50.0,
    this.selectedInterests = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'minAge': minAge,
      'maxAge': maxAge,
      'maxDistance': maxDistance,
      'selectedInterests': selectedInterests,
    };
  }

  factory DiscoveryFilters.fromJson(Map<String, dynamic> json) {
    return DiscoveryFilters(
      minAge: json['minAge'] ?? 18,
      maxAge: json['maxAge'] ?? 99,
      maxDistance: (json['maxDistance'] ?? 50.0).toDouble(),
      selectedInterests: json['selectedInterests'] != null
          ? List<String>.from(json['selectedInterests'])
          : [],
    );
  }

  bool get hasActiveFilters {
    return minAge != 18 || maxAge != 99 || maxDistance != 50.0 || selectedInterests.isNotEmpty;
  }

  DiscoveryFilters copyWith({
    int? minAge,
    int? maxAge,
    double? maxDistance,
    List<String>? selectedInterests,
  }) {
    return DiscoveryFilters(
      minAge: minAge ?? this.minAge,
      maxAge: maxAge ?? this.maxAge,
      maxDistance: maxDistance ?? this.maxDistance,
      selectedInterests: selectedInterests ?? this.selectedInterests,
    );
  }
}

class ProfileAction {
  final String userId;
  final String action; // 'pass' or 'like'
  final DateTime timestamp;

  ProfileAction({
    required this.userId,
    required this.action,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'action': action,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ProfileAction.fromJson(Map<String, dynamic> json) {
    return ProfileAction(
      userId: json['userId'],
      action: json['action'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  bool isExpired(Duration expirationDuration) {
    return DateTime.now().difference(timestamp) > expirationDuration;
  }
}

class DiscoveryPreferencesService extends ChangeNotifier {
  static const String _seenProfilesKey = 'discovery_seen_profiles';
  static const String _filtersKey = 'discovery_filters';
  static const String _currentIndexKey = 'discovery_current_index';
  static const String _tutorialSeenKey = 'discovery_tutorial_seen';
  static const Duration _seenProfilesExpiration = Duration(hours: 24);

  SharedPreferences? _prefs;
  DiscoveryFilters _filters = DiscoveryFilters();
  List<ProfileAction> _profileActions = [];

  DiscoveryFilters get filters => _filters;
  List<String> get seenProfileIds => _profileActions.map((a) => a.userId).toList();
  List<String> get passedProfileIds =>
      _profileActions.where((a) => a.action == 'pass').map((a) => a.userId).toList();
  List<String> get likedProfileIds =>
      _profileActions.where((a) => a.action == 'like').map((a) => a.userId).toList();

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadFilters();
    await _loadProfileActions();
    await _cleanExpiredActions();
  }

  // Filter management
  Future<void> _loadFilters() async {
    final filtersJson = _prefs?.getString(_filtersKey);
    if (filtersJson != null) {
      try {
        final data = json.decode(filtersJson);
        _filters = DiscoveryFilters.fromJson(data);
      } catch (e) {
        debugPrint('Error loading filters: $e');
      }
    }
  }

  Future<void> updateFilters(DiscoveryFilters filters) async {
    _filters = filters;
    await _prefs?.setString(_filtersKey, json.encode(filters.toJson()));
    notifyListeners();
  }

  Future<void> clearFilters() async {
    _filters = DiscoveryFilters();
    await _prefs?.remove(_filtersKey);
    notifyListeners();
  }

  // Profile action tracking
  Future<void> _loadProfileActions() async {
    final actionsJson = _prefs?.getString(_seenProfilesKey);
    if (actionsJson != null) {
      try {
        final List<dynamic> actionsList = json.decode(actionsJson);
        _profileActions = actionsList
            .map((a) => ProfileAction.fromJson(a))
            .toList();
      } catch (e) {
        debugPrint('Error loading profile actions: $e');
      }
    }
  }

  Future<void> _saveProfileActions() async {
    final actionsJson = json.encode(
      _profileActions.map((a) => a.toJson()).toList(),
    );
    await _prefs?.setString(_seenProfilesKey, actionsJson);
  }

  Future<void> _cleanExpiredActions() async {
    final beforeCount = _profileActions.length;
    _profileActions = _profileActions
        .where((action) => !action.isExpired(_seenProfilesExpiration))
        .toList();

    if (_profileActions.length != beforeCount) {
      await _saveProfileActions();
      debugPrint('Cleaned ${beforeCount - _profileActions.length} expired profile actions');
    }
  }

  Future<void> recordProfileAction(String userId, String action) async {
    // Remove any existing action for this user
    _profileActions.removeWhere((a) => a.userId == userId);

    // Add new action
    _profileActions.add(ProfileAction(
      userId: userId,
      action: action,
      timestamp: DateTime.now(),
    ));

    await _saveProfileActions();
    notifyListeners();
  }

  Future<void> undoLastAction() async {
    if (_profileActions.isNotEmpty) {
      _profileActions.removeLast();
      await _saveProfileActions();
      notifyListeners();
    }
  }

  ProfileAction? getLastAction() {
    return _profileActions.isNotEmpty ? _profileActions.last : null;
  }

  bool hasSeenProfile(String userId) {
    return _profileActions.any((a) => a.userId == userId);
  }

  Future<void> clearSeenProfiles() async {
    _profileActions.clear();
    await _prefs?.remove(_seenProfilesKey);
    notifyListeners();
  }

  // Discovery state persistence
  Future<void> saveCurrentIndex(int index) async {
    await _prefs?.setInt(_currentIndexKey, index);
  }

  int? getSavedIndex() {
    return _prefs?.getInt(_currentIndexKey);
  }

  Future<void> clearSavedIndex() async {
    await _prefs?.remove(_currentIndexKey);
  }

  // Tutorial tracking
  bool get hasSeenTutorial => _prefs?.getBool(_tutorialSeenKey) ?? false;

  Future<void> markTutorialAsSeen() async {
    await _prefs?.setBool(_tutorialSeenKey, true);
    notifyListeners();
  }

  Future<void> resetTutorial() async {
    await _prefs?.remove(_tutorialSeenKey);
    notifyListeners();
  }

  // Get stats
  int get totalSeenCount => _profileActions.length;
  int get passedCount => passedProfileIds.length;
  int get likedCount => likedProfileIds.length;
}
