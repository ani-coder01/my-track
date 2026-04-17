// lib/services/app_open_tracker.dart
//
// Tracks ALL app opens (not just nudged ones). Used for risk scoring.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppOpen {
  final String packageName;
  final DateTime timestamp;

  AppOpen({required this.packageName, required this.timestamp});

  Map<String, dynamic> toJson() => {
    'pkg': packageName,
    'ts': timestamp.millisecondsSinceEpoch,
  };

  factory AppOpen.fromJson(Map<String, dynamic> j) => AppOpen(
    packageName: j['pkg'] as String,
    timestamp: DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
  );
}

class AppOpenTracker {
  static const _key = 'app_opens';

  /// Record an app open when the monitor detects it
  static Future<void> recordOpen(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    final opens = await _load(prefs);
    opens.add(AppOpen(packageName: packageName, timestamp: DateTime.now()));

    // Keep last 1000 opens only
    final trimmed = opens.length > 1000
        ? opens.sublist(opens.length - 1000)
        : opens;

    await prefs.setString(
        _key, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
  }

  /// Count how many times [packageName] was opened today (regardless of nudge)
  static Future<int> openCountToday(String packageName) async {
    final opens = await all();
    final today = DateTime.now();
    return opens.where((e) {
      return e.packageName == packageName &&
          e.timestamp.year == today.year &&
          e.timestamp.month == today.month &&
          e.timestamp.day == today.day;
    }).length;
  }

  /// Get all recorded opens
  static Future<List<AppOpen>> all() async {
    final prefs = await SharedPreferences.getInstance();
    return _load(prefs);
  }

  // ── Private ────────────────────────────────────────────────────────

  static Future<List<AppOpen>> _load(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AppOpen.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
