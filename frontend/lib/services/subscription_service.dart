import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

/// RevenueCat Configuration Constants
class RevenueCatConfig {
  // Entitlement identifier from RevenueCat dashboard
  static const String entitlementId = 'No BS Dating Unlimited';

  // Product identifiers (must match RevenueCat dashboard)
  static const String monthlyProductId = 'monthly';
  static const String yearlyProductId = 'yearly';

  // API Key - Use environment variable or fallback to test key
  static String get apiKey {
    final configKey = AppConfig.revenueCatApiKey;
    if (configKey.isNotEmpty) {
      return configKey;
    }
    // Fallback test key (replace with production key in release)
    return const String.fromEnvironment(
      'REVENUECAT_API_KEY',
      defaultValue: 'test_PuuhQUSxNSymRIYEHqJeSVuchDi',
    );
  }
}

class SubscriptionService extends ChangeNotifier {
  bool _hasPremiumAccess = false;
  bool _isLoading = false;
  bool _isRevenueCatConfigured = false;
  String? _currentUserId;

  // Customer info cache
  CustomerInfo? _customerInfo;
  Offerings? _offerings;

  // Getters
  bool get hasPremiumAccess => _hasPremiumAccess;
  bool get isLoading => _isLoading;
  bool get isFreeUser => !_hasPremiumAccess;
  @Deprecated('Use isFreeUser instead')
  bool get isDemoMode => !_hasPremiumAccess; // Legacy - kept for compatibility
  bool get isRevenueCatConfigured => _isRevenueCatConfigured;
  CustomerInfo? get customerInfo => _customerInfo;
  Offerings? get offerings => _offerings;
  String? get currentUserId => _currentUserId;

  /// Initialize RevenueCat SDK
  Future<void> initialize(String userId) async {
    try {
      _isLoading = true;
      _currentUserId = userId;
      notifyListeners();

      // Check if API key is available
      final apiKey = RevenueCatConfig.apiKey;
      if (apiKey.isEmpty) {
        debugPrint('RevenueCat: No API key configured. Running in demo-only mode.');
        _isRevenueCatConfigured = false;
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Configure RevenueCat
      final configuration = PurchasesConfiguration(apiKey)
        ..appUserID = userId;

      await Purchases.configure(configuration);

      // Enable debug logs in debug mode
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }

      _isRevenueCatConfigured = true;

      // Listen for customer info updates
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);

      // Fetch initial customer info and offerings
      await Future.wait([
        _fetchCustomerInfo(),
        _fetchOfferings(),
      ]);

      _isLoading = false;
      notifyListeners();

      debugPrint('RevenueCat: Initialized successfully for user $userId');
    } catch (e) {
      debugPrint('RevenueCat: Error initializing - $e');
      _isRevenueCatConfigured = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Handle customer info updates from RevenueCat
  void _onCustomerInfoUpdated(CustomerInfo info) {
    _customerInfo = info;
    _updatePremiumStatus(info);
    notifyListeners();
    debugPrint('RevenueCat: Customer info updated');
  }

  /// Update premium status based on customer info
  void _updatePremiumStatus(CustomerInfo info) {
    final entitlement = info.entitlements.all[RevenueCatConfig.entitlementId];
    _hasPremiumAccess = entitlement?.isActive ?? false;

    if (_hasPremiumAccess) {
      debugPrint('RevenueCat: User has premium access via ${entitlement?.productIdentifier}');
    }
  }

  /// Fetch customer info from RevenueCat
  Future<void> _fetchCustomerInfo() async {
    if (!_isRevenueCatConfigured) return;

    try {
      _customerInfo = await Purchases.getCustomerInfo();
      _updatePremiumStatus(_customerInfo!);
    } catch (e) {
      debugPrint('RevenueCat: Error fetching customer info - $e');
    }
  }

  /// Fetch available offerings
  Future<void> _fetchOfferings() async {
    if (!_isRevenueCatConfigured) return;

    try {
      _offerings = await Purchases.getOfferings();
      if (_offerings?.current != null) {
        debugPrint('RevenueCat: Loaded ${_offerings!.current!.availablePackages.length} packages');
      }
    } catch (e) {
      debugPrint('RevenueCat: Error fetching offerings - $e');
    }
  }

  /// Check subscription status
  Future<void> checkSubscriptionStatus() async {
    if (!_isRevenueCatConfigured) {
      _hasPremiumAccess = false;
      notifyListeners();
      return;
    }

    await _fetchCustomerInfo();
    notifyListeners();
  }

  /// Present the RevenueCat Paywall
  /// Returns true if a purchase was made, false otherwise
  Future<PaywallResult> presentPaywall({bool displayCloseButton = true}) async {
    if (!_isRevenueCatConfigured) {
      debugPrint('RevenueCat: Cannot present paywall - not configured');
      return PaywallResult.notPresented;
    }

    try {
      _isLoading = true;
      notifyListeners();

      final result = await RevenueCatUI.presentPaywall(
        displayCloseButton: displayCloseButton,
      );

      debugPrint('RevenueCat: Paywall result - $result');

      // Refresh customer info after paywall
      await _fetchCustomerInfo();

      _isLoading = false;
      notifyListeners();

      return result;
    } catch (e) {
      debugPrint('RevenueCat: Error presenting paywall - $e');
      _isLoading = false;
      notifyListeners();
      return PaywallResult.error;
    }
  }

  /// Present paywall if user doesn't have premium
  /// Returns true if user now has premium access
  Future<bool> presentPaywallIfNeeded() async {
    if (_hasPremiumAccess) {
      return true;
    }

    final result = await presentPaywall();
    return result == PaywallResult.purchased || result == PaywallResult.restored;
  }

  /// Purchase a specific package
  Future<bool> purchasePackage(Package package) async {
    if (!_isRevenueCatConfigured) {
      debugPrint('RevenueCat: Cannot purchase - not configured');
      return false;
    }

    try {
      _isLoading = true;
      notifyListeners();

      final purchaseParams = PurchaseParams.package(package);
      final result = await Purchases.purchase(purchaseParams);
      _customerInfo = result.customerInfo;
      _updatePremiumStatus(result.customerInfo);

      _isLoading = false;
      notifyListeners();

      return _hasPremiumAccess;
    } on PurchasesErrorCode catch (e) {
      debugPrint('RevenueCat: Purchase error code - $e');
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      debugPrint('RevenueCat: Purchase error - $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Legacy method for backward compatibility
  Future<void> purchaseSubscription() async {
    await presentPaywall();
  }

  /// Restore previous purchases
  Future<bool> restorePurchases() async {
    if (!_isRevenueCatConfigured) {
      debugPrint('RevenueCat: Cannot restore - not configured');
      return false;
    }

    try {
      _isLoading = true;
      notifyListeners();

      final customerInfo = await Purchases.restorePurchases();
      _customerInfo = customerInfo;
      _updatePremiumStatus(customerInfo);

      _isLoading = false;
      notifyListeners();

      return _hasPremiumAccess;
    } catch (e) {
      debugPrint('RevenueCat: Error restoring purchases - $e');
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Present the Customer Center for subscription management
  Future<void> presentCustomerCenter(BuildContext context) async {
    if (!_isRevenueCatConfigured) {
      debugPrint('RevenueCat: Cannot present customer center - not configured');
      _showNotConfiguredDialog(context);
      return;
    }

    try {
      await RevenueCatUI.presentCustomerCenter();
    } catch (e) {
      debugPrint('RevenueCat: Error presenting customer center - $e');
      // Fallback: show a simple subscription info dialog
      if (context.mounted) {
        _showSubscriptionInfoDialog(context);
      }
    }
  }

  void _showNotConfiguredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not Available'),
        content: const Text(
          'Subscription features are not available in this build. '
          'Please contact support for assistance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showSubscriptionInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Subscription Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_hasPremiumAccess
                ? 'You have an active subscription.'
                : 'You are on the free plan.'),
            if (_customerInfo != null) ...[
              const SizedBox(height: 16),
              Text('User ID: ${_customerInfo!.originalAppUserId}'),
              if (_hasPremiumAccess && _customerInfo!.latestExpirationDate != null)
                Text('Expires: ${_customerInfo!.latestExpirationDate}'),
            ],
          ],
        ),
        actions: [
          if (!_hasPremiumAccess)
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                presentPaywall();
              },
              child: const Text('Upgrade'),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              restorePurchases();
            },
            child: const Text('Restore Purchases'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Get monthly package from current offering
  Package? getMonthlyPackage() {
    return _offerings?.current?.monthly;
  }

  /// Get yearly package from current offering
  Package? getYearlyPackage() {
    return _offerings?.current?.annual;
  }

  /// Get all available packages
  List<Package> getAvailablePackages() {
    return _offerings?.current?.availablePackages ?? [];
  }

  /// Get subscription management URL (for web-based management)
  String? getManagementUrl() {
    return _customerInfo?.managementURL;
  }

  /// Check if user is eligible for introductory pricing
  /// Note: In RevenueCat SDK v9+, eligibility info is available on the StoreProduct
  Future<bool> checkTrialOrIntroEligibility(String productId) async {
    if (!_isRevenueCatConfigured) return false;

    try {
      // In v9+, intro eligibility is determined from the offerings/packages
      final packages = getAvailablePackages();
      for (final package in packages) {
        if (package.storeProduct.identifier == productId) {
          // Check if product has intro pricing available
          return package.storeProduct.introductoryPrice != null;
        }
      }
      return false;
    } catch (e) {
      debugPrint('RevenueCat: Error checking intro eligibility - $e');
      return false;
    }
  }

  // ============================================
  // Premium Access Checks (no free trial - pay to play)
  // ============================================

  // Check if action is allowed - requires premium
  bool canLike() {
    return _hasPremiumAccess;
  }

  bool canSendMessage() {
    return _hasPremiumAccess;
  }

  bool canViewProfiles() {
    return _hasPremiumAccess;
  }

  // Get remaining counts (-1 = unlimited for premium, 0 = none for free)
  int getLikesRemaining() {
    return _hasPremiumAccess ? -1 : 0;
  }

  int getMessagesRemaining() {
    return _hasPremiumAccess ? -1 : 0;
  }

  // Legacy methods - no longer track usage since there's no free trial
  Future<void> useLike() async {
    // No-op - premium users have unlimited
  }

  Future<void> useMessage() async {
    // No-op - premium users have unlimited
  }

  /// Clean up when logging out
  Future<void> logout() async {
    if (_isRevenueCatConfigured) {
      try {
        await Purchases.logOut();
      } catch (e) {
        debugPrint('RevenueCat: Error logging out - $e');
      }
    }

    _hasPremiumAccess = false;
    _customerInfo = null;
    _offerings = null;
    _currentUserId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Remove listener when service is disposed
    if (_isRevenueCatConfigured) {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfoUpdated);
    }
    super.dispose();
  }
}
