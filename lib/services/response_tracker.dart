// lib/services/response_tracker.dart
//
// Persists nudge responses to SharedPreferences.
// Powers Insights streaks and personalises future risk scores.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum NudgeDecision { skipped, proceeded }

class NudgeEvent {
  final String packageName;
  final String appName;
  final int riskScore;
  final NudgeDecision decision;
  final DateTime timestamp;

  NudgeEvent({
    required this.packageName,
    required this.appName,
    required this.riskScore,
    required this.decision,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'pkg':       packageName,
        'app':       appName,
        'risk':      riskScore,
        'decision':  decision.name,
        'ts':        timestamp.millisecondsSinceEpoch,
      };

  factory NudgeEvent.fromJson(Map<String, dynamic> j) => NudgeEvent(
        packageName: j['pkg']  as String,
        appName:     j['app']  as String,
        riskScore:   j['risk'] as int,
        decision:    NudgeDecision.values.byName(j['decision'] as String),
        timestamp:   DateTime.fromMillisecondsSinceEpoch(j['ts'] as int),
      );
}

class ResponseTracker {
  static const _key = 'nudge_events';

  // ── Write ──────────────────────────────────────────────────────────────

  static Future<void> record(NudgeEvent event) async {
    final prefs  = await SharedPreferences.getInstance();
    final events = await _load(prefs);
    events.add(event);
    // Keep last 500 events only
    final trimmed = events.length > 500
        ? events.sublist(events.length - 500)
        : events;
    await prefs.setString(
        _key, jsonEncode(trimmed.map((e) => e.toJson()).toList()));
  }

  // ── Read ───────────────────────────────────────────────────────────────

  static Future<List<NudgeEvent>> all() async {
    final prefs = await SharedPreferences.getInstance();
    return _load(prefs);
  }

  /// How many times was [packageName] opened today?
  static Future<int> openCountToday(String packageName) async {
    final events = await all();
    final today  = DateTime.now();
    return events.where((e) {
      return e.packageName == packageName &&
          e.timestamp.year  == today.year &&
          e.timestamp.month == today.month &&
          e.timestamp.day   == today.day;
    }).length;
  }

  /// Total ₹ saved (skipped nudges × avg spend)
  static Future<double> totalSaved(
      Map<String, double> avgSpendMap) async {
    final events = await all();
    double total = 0;
    for (final e in events) {
      if (e.decision == NudgeDecision.skipped) {
        total += avgSpendMap[e.packageName] ?? 0;
      }
    }
    return total;
  }

  /// Current skip streak (consecutive days with ≥1 skip and 0 proceeds)
  static Future<int> skipStreak() async {
    final events = await all();
    if (events.isEmpty) return 0;

    int streak = 0;
    DateTime cursor = DateTime.now();

    while (true) {
      final dayEvents = events.where((e) =>
          e.timestamp.year  == cursor.year &&
          e.timestamp.month == cursor.month &&
          e.timestamp.day   == cursor.day);

      if (dayEvents.isEmpty) break;
      final hasSkip     = dayEvents.any((e) => e.decision == NudgeDecision.skipped);
      final hasProceeded = dayEvents.any((e) => e.decision == NudgeDecision.proceeded);
      if (!hasSkip || hasProceeded) break;

      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  // ── Private ────────────────────────────────────────────────────────────

  static Future<List<NudgeEvent>> _load(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => NudgeEvent.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}
