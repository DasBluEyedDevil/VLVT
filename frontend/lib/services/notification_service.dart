import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nobsdating/services/auth_service.dart';
import 'package:nobsdating/config/app_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    print('📬 Background message received: ${message.messageId}');
    print('   Title: ${message.notification?.title}');
    print('   Body: ${message.notification?.body}');
    print('   Data: ${message.data}');
  }
}

/// Service for handling push notifications
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  bool _initialized = false;

  /// Callback for when user taps a notification
  Function(Map<String, dynamic> data)? onNotificationTap;

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_initialized) {
      if (kDebugMode) print('🔔 Notification service already initialized');
      return;
    }

    try {
      if (kDebugMode) print('🔔 Initializing notification service...');

      // Set up background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Request permission
      final permission = await _requestPermission();
      if (!permission) {
        if (kDebugMode) print('⚠️ Notification permission denied');
        _initialized = true;
        return;
      }

      // Get FCM token
      _fcmToken = await _firebaseMessaging.getToken();
      if (kDebugMode) print('📱 FCM Token: ${_fcmToken?.substring(0, 20)}...');

      // Register token with backend
      if (_fcmToken != null) {
        await _registerToken(_fcmToken!);
      }

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        if (kDebugMode) print('🔄 FCM Token refreshed');
        _fcmToken = newToken;
        _registerToken(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification taps when app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Check if app was opened from a terminated state via notification
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }

      _initialized = true;
      if (kDebugMode) print('✅ Notification service initialized successfully');
    } catch (error) {
      if (kDebugMode) print('❌ Failed to initialize notification service: $error');
      _initialized = true; // Mark as initialized even on error to prevent retry loops
    }
  }

  /// Initialize local notifications (for displaying notifications while app is in foreground)
  Future<void> _initializeLocalNotifications() async {
    // Android settings
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
    final iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // Will request explicitly
      requestBadgePermission: false,
      requestSoundPermission: false,
      onDidReceiveLocalNotification: (id, title, body, payload) async {
        // Handle iOS foreground notification (for older iOS versions)
      },
    );

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
        if (details.payload != null) {
          try {
            final data = jsonDecode(details.payload!);
            onNotificationTap?.call(data);
          } catch (e) {
            if (kDebugMode) print('Error parsing notification payload: $e');
          }
        }
      },
    );

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }
  }

  /// Create Android notification channels
  Future<void> _createNotificationChannels() async {
    // Messages channel
    const messagesChannel = AndroidNotificationChannel(
      'messages',
      'Messages',
      description: 'Notifications for new messages',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    // Matches channel
    const matchesChannel = AndroidNotificationChannel(
      'matches',
      'Matches',
      description: 'Notifications for new matches',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(messagesChannel);

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(matchesChannel);
  }

  /// Request notification permission
  Future<bool> _requestPermission() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
           settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Register FCM token with backend
  Future<void> _registerToken(String token) async {
    try {
      final authService = AuthService();
      final user = await authService.getCurrentUser();

      if (user == null) {
        if (kDebugMode) print('⚠️ No user logged in - cannot register FCM token');
        return;
      }

      final jwtToken = await authService.getToken();
      if (jwtToken == null) {
        if (kDebugMode) print('⚠️ No JWT token - cannot register FCM token');
        return;
      }

      final deviceType = Platform.isIOS ? 'ios' : 'android';

      final response = await http.post(
        Uri.parse('${AppConfig.chatServiceUrl}/fcm/register'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({
          'token': token,
          'deviceType': deviceType,
        }),
      );

      if (response.statusCode == 200) {
        if (kDebugMode) print('✅ FCM token registered with backend');
      } else {
        if (kDebugMode) print('❌ Failed to register FCM token: ${response.statusCode}');
      }
    } catch (error) {
      if (kDebugMode) print('❌ Error registering FCM token: $error');
    }
  }

  /// Unregister FCM token from backend
  Future<void> unregisterToken() async {
    if (_fcmToken == null) return;

    try {
      final authService = AuthService();
      final jwtToken = await authService.getToken();
      if (jwtToken == null) return;

      await http.post(
        Uri.parse('${AppConfig.chatServiceUrl}/fcm/unregister'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({
          'token': _fcmToken,
        }),
      );

      if (kDebugMode) print('✅ FCM token unregistered from backend');
    } catch (error) {
      if (kDebugMode) print('❌ Error unregistering FCM token: $error');
    }
  }

  /// Handle foreground messages (app is open)
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    if (kDebugMode) {
      print('📬 Foreground message received: ${message.messageId}');
      print('   Title: ${message.notification?.title}');
      print('   Body: ${message.notification?.body}');
      print('   Data: ${message.data}');
    }

    // Show local notification
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null) {
      final channelId = message.data['type'] == 'match' ? 'matches' : 'messages';

      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelId == 'matches' ? 'Matches' : 'Messages',
            channelDescription: channelId == 'matches'
                ? 'Notifications for new matches'
                : 'Notifications for new messages',
            icon: '@mipmap/ic_launcher',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    }
  }

  /// Handle notification tap (app opened from notification)
  void _handleNotificationTap(RemoteMessage message) {
    if (kDebugMode) print('👆 Notification tapped: ${message.data}');
    onNotificationTap?.call(message.data);
  }

  /// Get current FCM token
  String? get fcmToken => _fcmToken;

  /// Check if notifications are enabled
  Future<bool> areNotificationsEnabled() async {
    final settings = await _firebaseMessaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
           settings.authorizationStatus == AuthorizationStatus.provisional;
  }
}
