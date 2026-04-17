// lib/services/behavior_engine.dart
//
// Watched-app registry + RiskScorer
// Risk score 0–100 → ≥50 triggers a nudge

class WatchedApp {
  final String name;
  final double avgSpend;   // average single-session spend in ₹
  final String category;   // food | shopping | entertainment | payments

  const WatchedApp({
    required this.name,
    required this.avgSpend,
    required this.category,
  });
}

class BehaviorEngine {
  // ── Watched-app registry ───────────────────────────────────────────────
  static const Map<String, WatchedApp> watchedApps = {
    'com.application.zomato': WatchedApp(
        name: 'Zomato', avgSpend: 350, category: 'food'),
    'in.swiggy.android': WatchedApp(
        name: 'Swiggy', avgSpend: 320, category: 'food'),
    'com.amazon.mShop.android.shopping': WatchedApp(
        name: 'Amazon', avgSpend: 1200, category: 'shopping'),
    'com.flipkart.android': WatchedApp(
        name: 'Flipkart', avgSpend: 900, category: 'shopping'),
    'com.myntra.android': WatchedApp(
        name: 'Myntra', avgSpend: 1500, category: 'shopping'),
    'com.bms.bmsapp': WatchedApp(
        name: 'BookMyShow', avgSpend: 600, category: 'entertainment'),
    'com.bigbasket.mobileapp': WatchedApp(
        name: 'BigBasket', avgSpend: 800, category: 'grocery'),
    'com.phonepe.app': WatchedApp(
        name: 'PhonePe', avgSpend: 500, category: 'payments'),
    'net.one97.paytm': WatchedApp(
        name: 'Paytm', avgSpend: 500, category: 'payments'),
    'com.google.android.apps.nbu.paisa.user': WatchedApp(
        name: 'Google Pay', avgSpend: 500, category: 'payments'),
  };

  // ── Risk scorer ────────────────────────────────────────────────────────
  /// Returns a risk score 0–100.
  /// Parameters:
  ///   [packageName]      — the opened app's package
  ///   [openCountToday]   — how many times user opened this app today
  ///   [budgetUsedPct]    — fraction of monthly budget already spent (0.0–1.0)
  ///   [monthlyLeakage]   — total avoidable monthly spend in ₹
  static int score({
    required String packageName,
    required int openCountToday,
    required double budgetUsedPct,
    required double monthlyLeakage,
  }) {
    final app = watchedApps[packageName];
    if (app == null) return 0;

    int risk = 30; // base risk for any watched-app open

    // Category multiplier
    switch (app.category) {
      case 'food':          risk += 15; break;
      case 'shopping':      risk += 20; break;
      case 'entertainment': risk += 10; break;
      case 'payments':      risk += 5;  break;
    }

    // Time of day — late night impulse bonus
    final hour = DateTime.now().hour;
    if (hour >= 22 || hour < 6)  risk += 20; // late night / early morning
    else if (hour >= 18)          risk += 10; // evening

    // Repeat opens today
    if (openCountToday >= 3)      risk += 15;
    else if (openCountToday >= 2) risk += 8;

    // Budget pressure
    if (budgetUsedPct >= 0.8)     risk += 20;
    else if (budgetUsedPct >= 0.6) risk += 10;

    // High existing leakage
    if (monthlyLeakage > 10000)   risk += 10;
    else if (monthlyLeakage > 5000) risk += 5;

    return risk.clamp(0, 100);
  }

  // ── Savings projection ─────────────────────────────────────────────────
  /// How much the avg spend would compound to in [years] years at 12% p.a.
  static double sipAlternative(String packageName, {int years = 5}) {
    final app = watchedApps[packageName];
    if (app == null) return 0;
    final monthly = app.avgSpend;
    final months  = years * 12;
    const r       = 0.12 / 12;
    return monthly * ((((1 + r) * ((1 + r) * months - 1)) / r));
  }
}
