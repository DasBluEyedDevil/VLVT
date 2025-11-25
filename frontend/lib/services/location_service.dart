/// Location Service for Geolocation Features
/// Handles location permissions, tracking, and updates
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'profile_api_service.dart';

/// Represents a geographic location
class GeoLocation {
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  GeoLocation({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  factory GeoLocation.fromPosition(Position position) {
    return GeoLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
    );
  }

  /// Calculate distance to another location in kilometers
  double distanceTo(GeoLocation other) {
    return Geolocator.distanceBetween(
      latitude,
      longitude,
      other.latitude,
      other.longitude,
    ) / 1000.0; // Convert meters to kilometers
  }

  @override
  String toString() => 'GeoLocation($latitude, $longitude)';
}

/// Location service for handling geolocation features
class LocationService extends ChangeNotifier {
  final ProfileApiService _profileService;

  GeoLocation? _currentLocation;
  bool _isLocationEnabled = false;
  bool _hasPermission = false;
  bool _isUpdating = false;
  Timer? _periodicUpdateTimer;

  // Getters
  GeoLocation? get currentLocation => _currentLocation;
  bool get isLocationEnabled => _isLocationEnabled;
  bool get hasPermission => _hasPermission;
  bool get isUpdating => _isUpdating;

  LocationService(this._profileService);

  /// Initialize location service
  Future<void> initialize() async {
    await checkPermission();
    if (_hasPermission) {
      await updateLocation();
      startPeriodicUpdates();
    }
  }

  /// Check if location services are enabled
  Future<bool> checkLocationService() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      _isLocationEnabled = serviceEnabled;
      notifyListeners();
      return serviceEnabled;
    } catch (e) {
      debugPrint('Error checking location service: $e');
      return false;
    }
  }

  /// Check location permission status
  Future<bool> checkPermission() async {
    try {
      final permission = await Permission.location.status;
      _hasPermission = permission.isGranted || permission.isLimited;
      notifyListeners();
      return _hasPermission;
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      return false;
    }
  }

  /// Request location permission
  Future<bool> requestPermission() async {
    try {
      // First check if location services are enabled
      final serviceEnabled = await checkLocationService();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        return false;
      }

      // Request permission
      final status = await Permission.location.request();
      _hasPermission = status.isGranted || status.isLimited;

      if (_hasPermission) {
        // Initialize location tracking
        await updateLocation();
        startPeriodicUpdates();
      }

      notifyListeners();
      return _hasPermission;
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      return false;
    }
  }

  /// Get current location
  Future<GeoLocation?> getCurrentLocation() async {
    try {
      if (!_hasPermission) {
        final granted = await requestPermission();
        if (!granted) {
          debugPrint('Location permission not granted');
          return null;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      final location = GeoLocation.fromPosition(position);
      _currentLocation = location;
      notifyListeners();

      debugPrint('Got location: ${location.latitude}, ${location.longitude}');
      return location;
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }

  /// Update location and send to backend
  Future<bool> updateLocation() async {
    if (_isUpdating) return false;

    _isUpdating = true;
    notifyListeners();

    try {
      final location = await getCurrentLocation();

      if (location == null) {
        _isUpdating = false;
        notifyListeners();
        return false;
      }

      // Update location in backend
      final success = await _profileService.updateLocation(
        location.latitude,
        location.longitude,
      );

      _isUpdating = false;
      notifyListeners();

      if (success) {
        debugPrint('Location updated successfully');
      } else {
        debugPrint('Failed to update location in backend');
      }

      return success;
    } catch (e) {
      debugPrint('Error updating location: $e');
      _isUpdating = false;
      notifyListeners();
      return false;
    }
  }

  /// Start periodic location updates (every 15 minutes)
  void startPeriodicUpdates() {
    stopPeriodicUpdates(); // Stop any existing timer

    _periodicUpdateTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => updateLocation(),
    );

    debugPrint('Started periodic location updates (every 15 minutes)');
  }

  /// Stop periodic location updates
  void stopPeriodicUpdates() {
    _periodicUpdateTimer?.cancel();
    _periodicUpdateTimer = null;
    debugPrint('Stopped periodic location updates');
  }

  /// Calculate distance to another location in kilometers
  double? distanceTo(double latitude, double longitude) {
    if (_currentLocation == null) return null;

    final targetLocation = GeoLocation(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
    );

    return _currentLocation!.distanceTo(targetLocation);
  }

  /// Format distance for display
  static String formatDistance(double distanceKm) {
    if (distanceKm < 1.0) {
      return '${(distanceKm * 1000).round()}m away';
    } else if (distanceKm < 10.0) {
      return '${distanceKm.toStringAsFixed(1)}km away';
    } else {
      return '${distanceKm.round()}km away';
    }
  }

  @override
  void dispose() {
    stopPeriodicUpdates();
    super.dispose();
  }
}
