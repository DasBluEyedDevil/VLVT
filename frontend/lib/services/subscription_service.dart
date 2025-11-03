import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../config/app_config.dart';

class SubscriptionService extends ChangeNotifier {
  bool _hasPremiumAccess = false;
  bool _isLoading = false;
  
  bool get hasPremiumAccess => _hasPremiumAccess;
  bool get isLoading => _isLoading;
  
  // Initialize RevenueCat
  Future<void> initialize(String userId) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // Initialize RevenueCat with your API key from config
      // Make sure to set different keys for iOS and Android in production
      if (AppConfig.revenueCatApiKey == 'YOUR_REVENUECAT_API_KEY') {
        debugPrint('WARNING: Using default RevenueCat API key. Please configure a real key.');
      }
      final configuration = PurchasesConfiguration(
        AppConfig.revenueCatApiKey,
      );
      
      await Purchases.configure(configuration);
      await Purchases.logIn(userId);
      
      // Check subscription status
      await checkSubscriptionStatus();
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing RevenueCat: $e');
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<void> checkSubscriptionStatus() async {
    try {
      final customerInfo = await Purchases.getCustomerInfo();
      
      // Check for 'premium_access' entitlement
      _hasPremiumAccess = customerInfo.entitlements.all['premium_access']?.isActive ?? false;
      
      notifyListeners();
    } catch (e) {
      debugPrint('Error checking subscription status: $e');
      _hasPremiumAccess = false;
      notifyListeners();
    }
  }
  
  Future<void> purchaseSubscription() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // Get available offerings
      final offerings = await Purchases.getOfferings();
      
      if (offerings.current != null && offerings.current!.availablePackages.isNotEmpty) {
        // Purchase the first available package
        final package = offerings.current!.availablePackages.first;
        
        await Purchases.purchasePackage(package);
        
        // Check updated subscription status
        await checkSubscriptionStatus();
      }
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error purchasing subscription: $e');
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<void> restorePurchases() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      await Purchases.restorePurchases();
      await checkSubscriptionStatus();
      
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
      _isLoading = false;
      notifyListeners();
    }
  }
}
