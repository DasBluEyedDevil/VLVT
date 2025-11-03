import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

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
      
      // Initialize RevenueCat with your API keys
      // For iOS: use your iOS API key
      // For Android: use your Android API key
      final configuration = PurchasesConfiguration(
        'YOUR_REVENUECAT_API_KEY', // Replace with actual key
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
