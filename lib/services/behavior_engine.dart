// lib/services/behavior_engine.dart
//
// Watched-app registry + RiskScorer
// Risk score 0–100 → ≥50 triggers a nudge

import 'dart:math' as math;
import 'watched_apps_registry.dart';

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
  // CONSOLIDATED: Uses WatchedAppsRegistry from watched_apps_registry.dart
  static Map<String, WatchedApp> get watchedApps {
    final result = <String, WatchedApp>{};
    for (final a in WatchedAppsRegistry.apps) {
      result[a.packageName] = WatchedApp(
        name: a.name,
        avgSpend: a.avgSpend,
        category: a.category,
      );
    }
    return result;
  }

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
    if (hour >= 22 || hour < 6) {
      risk += 20; // late night / early morning
    } else if (hour >= 18)          risk += 10; // evening

    // Repeat opens today
    if (openCountToday >= 3) {
      risk += 15;
    } else if (openCountToday >= 2) risk += 8;

    // Budget pressure
    if (budgetUsedPct >= 0.8) {
      risk += 20;
    } else if (budgetUsedPct >= 0.6) risk += 10;

    // High existing leakage
    if (monthlyLeakage > 10000) {
      risk += 10;
    } else if (monthlyLeakage > 5000) risk += 5;

    return risk.clamp(0, 100);
  }

  // ── Savings projection ─────────────────────────────────────────────────
  /// How much the avg spend would compound to in [years] years at 12% p.a.
  /// Uses FV of annuity-due formula: P * [((1+r)^n - 1) / r] * (1+r)
  static double sipAlternative(String packageName, {int years = 5}) {
    final app = watchedApps[packageName];
    if (app == null) return 0;
    final monthly = app.avgSpend;
    final months  = years * 12;
    const r       = 0.12 / 12;
    return monthly * ((math.pow(1 + r, months) - 1) / r) * (1 + r);
  }
}
