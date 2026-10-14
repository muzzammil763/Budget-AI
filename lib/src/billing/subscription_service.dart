import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Budget AI Premium tiers, from lowest to highest.
enum PremiumTier { free, lite, plus, pro }

enum PremiumPeriod { monthly, yearly }

/// One purchasable Play base plan, e.g. Plus · Yearly.
class PremiumPlanOption {
  const PremiumPlanOption({
    required this.tier,
    required this.period,
    required this.package,
  });

  final PremiumTier tier;
  final PremiumPeriod period;
  final Package package;

  String get price => package.storeProduct.priceString;

  /// Google Play subscription id without the base plan (`budget_ai_plus`).
  String get subscriptionId => package.storeProduct.identifier.split(':').first;

  /// The monthly equivalent of a yearly price, for the paywall's subtitle.
  String? get monthlyEquivalent {
    if (period != PremiumPeriod.yearly) return null;
    return package.storeProduct.pricePerMonthString;
  }
}

enum PremiumPurchaseOutcome { purchased, cancelled, pending, failed }

/// Owns the RevenueCat SDK on Android: ties purchases to the signed-in
/// Supabase user and exposes the active Premium tier.
///
/// The server stays the source of truth for AI limits; this only drives the
/// paywall and Budget Hub UI. It is disabled on iOS (no paywall yet) and
/// whenever the build has no RevenueCat SDK key.
class SubscriptionService {
  SubscriptionService._();

  static final SubscriptionService instance = SubscriptionService._();

  /// Public RevenueCat Android SDK key (`goog_...`), passed at build time with
  /// `--dart-define=REVENUECAT_ANDROID_KEY=goog_...`. Safe to ship in the app.
  static const _androidKey = String.fromEnvironment('REVENUECAT_ANDROID_KEY');

  /// RevenueCat entitlement identifiers, highest first.
  static const _entitlements = <String, PremiumTier>{
    'pro': PremiumTier.pro,
    'plus': PremiumTier.plus,
    'lite': PremiumTier.lite,
  };

  final ValueNotifier<PremiumTier> tier = ValueNotifier(PremiumTier.free);
  final ValueNotifier<CustomerInfo?> customerInfo = ValueNotifier(null);

  bool _configured = false;
  String? _loggedInUserId;
  StreamSubscription<AuthState>? _authSubscription;

  bool get isAvailable =>
      !kIsWeb && Platform.isAndroid && _androidKey.isNotEmpty;
  bool get isConfigured => _configured;

  Future<void> initialize() async {
    if (!isAvailable || _configured) return;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      final configuration = PurchasesConfiguration(_androidKey)
        ..appUserID = user?.id;
      await Purchases.configure(configuration);
      _configured = true;
      _loggedInUserId = user?.id;
      Purchases.addCustomerInfoUpdateListener(_applyCustomerInfo);
      _authSubscription = Supabase.instance.client.auth.onAuthStateChange
          .listen((state) => unawaited(_syncUser(state.session?.user)));
      await refresh();
    } catch (error) {
      debugPrint('[SubscriptionService] RevenueCat setup failed: $error');
    }
  }

  /// Purchases belong to the Budget AI account, so the RevenueCat user follows
  /// the Supabase session.
  Future<void> _syncUser(User? user) async {
    if (!_configured || user?.id == _loggedInUserId) return;
    try {
      if (user == null) {
        await Purchases.logOut();
        _applyCustomerInfo(null);
      } else {
        final result = await Purchases.logIn(user.id);
        _applyCustomerInfo(result.customerInfo);
      }
      _loggedInUserId = user?.id;
    } catch (error) {
      debugPrint('[SubscriptionService] Could not switch user: $error');
    }
  }

  Future<void> refresh() async {
    if (!_configured) return;
    try {
      _applyCustomerInfo(await Purchases.getCustomerInfo());
    } catch (error) {
      debugPrint('[SubscriptionService] Could not load customer info: $error');
    }
  }

  void _applyCustomerInfo(CustomerInfo? info) {
    customerInfo.value = info;
    tier.value = tierFor(info);
  }

  /// The six Play base plans from the current RevenueCat offering.
  Future<List<PremiumPlanOption>> loadPlans() async {
    if (!_configured) return const [];
    final offerings = await Purchases.getOfferings();
    final packages = offerings.current?.availablePackages ?? const <Package>[];
    return [
      for (final package in packages)
        if (planFor(package.storeProduct.identifier, package.packageType)
            case final (PremiumTier, PremiumPeriod) plan)
          PremiumPlanOption(tier: plan.$1, period: plan.$2, package: package),
    ];
  }

  /// Buys [option]. Moving up a tier takes effect now with prorated credit;
  /// moving down waits for the current period to end.
  Future<PremiumPurchaseOutcome> purchase(PremiumPlanOption option) async {
    if (!_configured) return PremiumPurchaseOutcome.failed;
    final current = _activeSubscriptionId();
    final changeInfo = current != null && current != option.subscriptionId
        ? StoreProductChangeInfo(
            current,
            replacementMode: option.tier.index > tier.value.index
                ? StoreReplacementMode.chargeProratedPrice
                : StoreReplacementMode.deferred,
          )
        : null;
    try {
      final result = await Purchases.purchase(
        PurchaseParams.package(option.package, productChangeInfo: changeInfo),
      );
      _applyCustomerInfo(result.customerInfo);
      return PremiumPurchaseOutcome.purchased;
    } on PlatformException catch (error) {
      switch (PurchasesErrorHelper.getErrorCode(error)) {
        case PurchasesErrorCode.purchaseCancelledError:
          return PremiumPurchaseOutcome.cancelled;
        case PurchasesErrorCode.paymentPendingError:
          return PremiumPurchaseOutcome.pending;
        default:
          debugPrint('[SubscriptionService] Purchase failed: $error');
          return PremiumPurchaseOutcome.failed;
      }
    }
  }

  /// Re-links Play purchases made with this Google account to the signed-in
  /// Budget AI account. Returns the restored tier.
  Future<PremiumTier> restore() async {
    if (!_configured) return PremiumTier.free;
    _applyCustomerInfo(await Purchases.restorePurchases());
    return tier.value;
  }

  String? _activeSubscriptionId() {
    final active = customerInfo.value?.entitlements.active ?? const {};
    for (final key in _entitlements.keys) {
      final entitlement = active[key];
      if (entitlement != null) {
        return entitlement.productIdentifier.split(':').first;
      }
    }
    return null;
  }

  /// Maps a Play product (`budget_ai_plus:yearly`) to its tier and period.
  @visibleForTesting
  static (PremiumTier, PremiumPeriod)? planFor(
    String productIdentifier,
    PackageType packageType,
  ) {
    final parts = productIdentifier.toLowerCase().split(':');
    final tier = switch (parts.first) {
      'budget_ai_lite' => PremiumTier.lite,
      'budget_ai_plus' => PremiumTier.plus,
      'budget_ai_pro' => PremiumTier.pro,
      _ => null,
    };
    if (tier == null) return null;
    final basePlan = parts.length > 1 ? parts[1] : '';
    final PremiumPeriod? period = basePlan.contains('year')
        ? PremiumPeriod.yearly
        : basePlan.contains('month')
        ? PremiumPeriod.monthly
        : switch (packageType) {
            PackageType.annual => PremiumPeriod.yearly,
            PackageType.monthly => PremiumPeriod.monthly,
            _ => null,
          };
    return period == null ? null : (tier, period);
  }

  @visibleForTesting
  static PremiumTier tierFor(CustomerInfo? info) {
    final active = info?.entitlements.active ?? const {};
    for (final entry in _entitlements.entries) {
      if (active.containsKey(entry.key)) return entry.value;
    }
    return PremiumTier.free;
  }

  Future<void> dispose() async {
    await _authSubscription?.cancel();
  }
}
