// lib/services/watched_apps_registry.dart
//
// Single source of truth for all watched spending apps.
// IMPORTANT: Keep in sync with AppMonitorService.WATCHED_APPS in Kotlin!

class WatchedAppInfo {
  final String packageName;
  final String name;
  final double avgSpend; // in ₹
  final String category; // food | shopping | entertainment | payments | grocery

  const WatchedAppInfo({
    required this.packageName,
    required this.name,
    required this.avgSpend,
    required this.category,
  });
}

/// Registry of all apps to monitor and their spend profiles
class WatchedAppsRegistry {
  static const List<WatchedAppInfo> apps = [
    WatchedAppInfo(
      packageName: 'com.application.zomato',
      name: 'Zomato',
      avgSpend: 350,
      category: 'food',
    ),
    WatchedAppInfo(
      packageName: 'in.swiggy.android',
      name: 'Swiggy',
      avgSpend: 320,
      category: 'food',
    ),
    WatchedAppInfo(
      packageName: 'com.grofers.customerapp',
      name: 'Blinkit',
      avgSpend: 400,
      category: 'grocery',
    ),
    WatchedAppInfo(
      packageName: 'com.zeptconsumerapp',
      name: 'Zepto',
      avgSpend: 350,
      category: 'grocery',
    ),
    WatchedAppInfo(
      packageName: 'com.amazon.mShop.android.shopping',
      name: 'Amazon',
      avgSpend: 1200,
      category: 'shopping',
    ),
    WatchedAppInfo(
      packageName: 'com.flipkart.android',
      name: 'Flipkart',
      avgSpend: 900,
      category: 'shopping',
    ),
    WatchedAppInfo(
      packageName: 'com.myntra.android',
      name: 'Myntra',
      avgSpend: 1500,
      category: 'shopping',
    ),
    WatchedAppInfo(
      packageName: 'com.ril.ajio',
      name: 'Ajio',
      avgSpend: 1200,
      category: 'shopping',
    ),
    WatchedAppInfo(
      packageName: 'com.fsn.nykaa',
      name: 'Nykaa',
      avgSpend: 1800,
      category: 'shopping',
    ),
    WatchedAppInfo(
      packageName: 'com.bms.bmsapp',
      name: 'BookMyShow',
      avgSpend: 600,
      category: 'entertainment',
    ),
    WatchedAppInfo(
      packageName: 'com.bigbasket.mobileapp',
      name: 'BigBasket',
      avgSpend: 800,
      category: 'grocery',
    ),
    WatchedAppInfo(
      packageName: 'com.phonepe.app',
      name: 'PhonePe',
      avgSpend: 500,
      category: 'payments',
    ),
    WatchedAppInfo(
      packageName: 'net.one97.paytm',
      name: 'Paytm',
      avgSpend: 500,
      category: 'payments',
    ),
    WatchedAppInfo(
      packageName: 'com.google.android.apps.nbu.paisa.user',
      name: 'Google Pay',
      avgSpend: 500,
      category: 'payments',
    ),
  ];

  /// Look up app info by package name
  static WatchedAppInfo? lookup(String packageName) {
    try {
      return apps.firstWhere((a) => a.packageName == packageName);
    } catch (_) {
      return null;
    }
  }

  /// Check if a package is watched
  static bool isWatched(String packageName) => lookup(packageName) != null;

  /// Get all package names
  static List<String> get allPackages => apps.map((a) => a.packageName).toList();

  /// Get all package names as a map (for compatibility with BehaviorEngine)
  static Map<String, String> get asPackageNameMap =>
      {for (var a in apps) a.packageName: a.name};
}
