import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Budget AI Premium tiers, from lowest to highest.
enum PremiumTier { free, lite, plus, pro }

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

  bool get isAvailable => Platform.isAndroid && _androidKey.isNotEmpty;
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
