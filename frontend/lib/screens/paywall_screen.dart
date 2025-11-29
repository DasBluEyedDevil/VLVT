import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import '../services/subscription_service.dart';
import '../services/auth_service.dart';
import '../services/analytics_service.dart';
import '../config/app_colors.dart';

class PaywallScreen extends StatefulWidget {
  final bool showBackButton;
  final String? source;

  const PaywallScreen({super.key, this.showBackButton = false, this.source});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();

  /// Show RevenueCat paywall if configured, otherwise show custom paywall
  static Future<void> show(BuildContext context, {String? source}) async {
    final subscriptionService = context.read<SubscriptionService>();

    // Track paywall view
    AnalyticsService.logPaywallViewed(source: source);

    if (subscriptionService.isRevenueCatConfigured) {
      // Use RevenueCat's native paywall
      await subscriptionService.presentPaywall();
    } else {
      // Fallback to custom paywall screen
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PaywallScreen(showBackButton: true, source: source),
          ),
        );
      }
    }
  }
}

class _PaywallScreenState extends State<PaywallScreen> {
  int _selectedPlanIndex = 0; // 0 = yearly, 1 = monthly

  @override
  void initState() {
    super.initState();
    // Track paywall view
    AnalyticsService.logPaywallViewed(source: widget.source);
  }

  @override
  Widget build(BuildContext context) {
    final subscriptionService = context.watch<SubscriptionService>();
    final authService = context.watch<AuthService>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // If RevenueCat is configured, try to use native paywall
    if (subscriptionService.isRevenueCatConfigured) {
      return _buildRevenueCatPaywall(context, subscriptionService, isDark);
    }

    // Fallback: Custom paywall for when RevenueCat isn't configured
    return _buildCustomPaywall(context, subscriptionService, authService, isDark);
  }

  Widget _buildRevenueCatPaywall(
    BuildContext context,
    SubscriptionService subscriptionService,
    bool isDark,
  ) {
    final monthlyPackage = subscriptionService.getMonthlyPackage();
    final yearlyPackage = subscriptionService.getYearlyPackage();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Go Premium'),
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Icon(
                Icons.star,
                size: 80,
                color: AppColors.premium(context),
              ),
              const SizedBox(height: 16),
              const Text(
                'Unlock NoBS Dating Unlimited',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.success(context).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success(context).withValues(alpha: 0.3)),
                ),
                child: Text(
                  '7-day free trial included',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success(context),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Plan selection
              if (yearlyPackage != null || monthlyPackage != null) ...[
                const Text(
                  'Choose Your Plan',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // Yearly plan
                if (yearlyPackage != null)
                  _buildPlanCard(
                    context: context,
                    package: yearlyPackage,
                    isSelected: _selectedPlanIndex == 0,
                    onTap: () => setState(() => _selectedPlanIndex = 0),
                    isDark: isDark,
                    badge: 'Best Value',
                    savings: monthlyPackage != null
                        ? _calculateSavings(yearlyPackage, monthlyPackage)
                        : null,
                  ),

                if (yearlyPackage != null && monthlyPackage != null)
                  const SizedBox(height: 12),

                // Monthly plan
                if (monthlyPackage != null)
                  _buildPlanCard(
                    context: context,
                    package: monthlyPackage,
                    isSelected: _selectedPlanIndex == 1,
                    onTap: () => setState(() => _selectedPlanIndex = 1),
                    isDark: isDark,
                  ),

                const SizedBox(height: 24),
              ],

              // Features list
              _buildFeaturesList(context),
              const SizedBox(height: 32),

              // CTA Buttons
              if (subscriptionService.isLoading)
                const Center(child: CircularProgressIndicator())
              else ...[
                ElevatedButton(
                  onPressed: () async {
                    final package = _selectedPlanIndex == 0
                        ? yearlyPackage
                        : monthlyPackage;
                    if (package != null) {
                      final success = await subscriptionService.purchasePackage(package);
                      if (success && mounted) {
                        Navigator.of(context).pop();
                      }
                    } else {
                      // Fallback to native paywall
                      await subscriptionService.presentPaywall();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Subscribe Now',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () async {
                    final restored = await subscriptionService.restorePurchases();
                    if (restored && mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Purchases restored successfully!')),
                      );
                      Navigator.of(context).pop();
                    }
                  },
                  child: const Text(
                    'Restore Purchases',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'By subscribing, you agree to our Terms of Service and Privacy Policy. '
                'Subscription auto-renews unless cancelled at least 24 hours before the end of the current period.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCard({
    required BuildContext context,
    required Package package,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    String? badge,
    String? savings,
  }) {
    final storeProduct = package.storeProduct;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.primaryDark : AppColors.primaryLight).withValues(alpha: 0.1)
              : AppColors.surface(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? (isDark ? AppColors.primaryDark : AppColors.primaryLight)
                : Colors.grey.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            Row(
              children: [
                // Radio indicator
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected
                          ? (isDark ? AppColors.primaryDark : AppColors.primaryLight)
                          : Colors.grey,
                      width: 2,
                    ),
                  ),
                  child: isSelected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark ? AppColors.primaryDark : AppColors.primaryLight,
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 16),
                // Plan details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getPackageTitle(package),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? (isDark ? AppColors.primaryDark : AppColors.primaryLight)
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        storeProduct.priceString,
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      if (savings != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          savings,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.success(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            // Badge
            if (badge != null)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getPackageTitle(Package package) {
    switch (package.packageType) {
      case PackageType.annual:
        return 'Yearly';
      case PackageType.monthly:
        return 'Monthly';
      case PackageType.weekly:
        return 'Weekly';
      case PackageType.lifetime:
        return 'Lifetime';
      default:
        return package.storeProduct.title;
    }
  }

  String? _calculateSavings(Package yearlyPackage, Package monthlyPackage) {
    try {
      final yearlyPrice = yearlyPackage.storeProduct.price;
      final monthlyPrice = monthlyPackage.storeProduct.price;
      final yearlyEquivalentMonthly = yearlyPrice / 12;
      final savingsPercent = ((monthlyPrice - yearlyEquivalentMonthly) / monthlyPrice * 100).round();
      if (savingsPercent > 0) {
        return 'Save $savingsPercent%';
      }
    } catch (e) {
      // Ignore calculation errors
    }
    return null;
  }

  Widget _buildFeaturesList(BuildContext context) {
    final features = [
      ('Unlimited likes every day', Icons.favorite),
      ('Unlimited messages', Icons.chat),
      ('See who likes you', Icons.visibility),
      ('Priority in discovery', Icons.trending_up),
      ('No ads', Icons.block),
      ('Priority support', Icons.support_agent),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Premium Features',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        ...features.map((feature) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.check_circle,
                color: AppColors.success(context),
                size: 24,
              ),
              const SizedBox(width: 12),
              Icon(feature.$2, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  feature.$1,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildCustomPaywall(
    BuildContext context,
    SubscriptionService subscriptionService,
    AuthService authService,
    bool isDark,
  ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Go Premium'),
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: [
          if (!widget.showBackButton)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: () async {
                await authService.signOut();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.star,
                size: 80,
                color: AppColors.premium(context),
              ),
              const SizedBox(height: 16),
              const Text(
                'Unlock NoBS Dating Premium',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.success(context).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.success(context).withValues(alpha: 0.3)),
                ),
                child: Text(
                  '7-day free trial included',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success(context),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      isDark ? AppColors.primaryDark : AppColors.primaryLight,
                      (isDark ? AppColors.primaryDark : AppColors.primaryLight).withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: (isDark ? AppColors.primaryDark : AppColors.primaryLight).withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Column(
                  children: [
                    Text(
                      '\$9.99/month',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Cancel anytime',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildFeaturesList(context),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  'Subscriptions not available in this build',
                  style: TextStyle(
                    color: AppColors.textSecondary(context),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
