import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'response_tracker.dart';
import 'db_service.dart';

class MonthlySnapshot {
  final String month; // YYYY-MM
  final double essential;
  final double avoidable;
  final double impulse;
  final double salary;
  final int nudgeSkips;
  final int nudgeProceeds;

  MonthlySnapshot({
    required this.month,
    required this.essential,
    required this.avoidable,
    required this.impulse,
    required this.salary,
    required this.nudgeSkips,
    required this.nudgeProceeds,
  });

  Map<String, dynamic> toJson() => {
    'month': month,
    'essential': essential,
    'avoidable': avoidable,
    'impulse': impulse,
    'salary': salary,
    'nudgeSkips': nudgeSkips,
    'nudgeProceeds': nudgeProceeds,
  };

  factory MonthlySnapshot.fromJson(Map<String, dynamic> json) => MonthlySnapshot(
    month: json['month'] as String,
    essential: (json['essential'] as num).toDouble(),
    avoidable: (json['avoidable'] as num).toDouble(),
    impulse: (json['impulse'] as num).toDouble(),
    salary: (json['salary'] as num).toDouble(),
    nudgeSkips: json['nudgeSkips'] as int,
    nudgeProceeds: json['nudgeProceeds'] as int,
  );
}

class MonthlySnapshotService {
  static const _lastSnapshotKey = 'last_snapshot_month';

  /// Take a snapshot if the month has changed
  static Future<void> takeSnapshotIfNeeded(AppState state) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

      final lastMonth = prefs.getString(_lastSnapshotKey);
      if (lastMonth == currentMonth) {
        return; // Already took snapshot this month
      }

      // Calculate totals from expenses
      double essential = 0, avoidable = 0, impulse = 0;
      for (final expense in state.expenses) {
        final monthly = _monthlyEquiv(expense.amount, expense.frequency);
        if (expense.tag == 'essential') essential += monthly;
        else if (expense.tag == 'avoidable') avoidable += monthly;
        else if (expense.tag == 'impulse') impulse += monthly;
      }

      // Count nudge events
      final allEvents = await ResponseTracker.all();
      int skips = 0, proceeds = 0;

      for (final event in allEvents) {
        if (event.timestamp.year == now.year && event.timestamp.month == now.month) {
          if (event.decision == NudgeDecision.skipped) skips++;
          else if (event.decision == NudgeDecision.proceeded) proceeds++;
        }
      }

      // Create snapshot
      final snapshot = MonthlySnapshot(
        month: currentMonth,
        essential: essential,
        avoidable: avoidable,
        impulse: impulse,
        salary: state.monthlySalary,
        nudgeSkips: skips,
        nudgeProceeds: proceeds,
      );

      // Save snapshot
      await prefs.setString(
        'snapshot_$currentMonth',
        jsonEncode(snapshot.toJson()),
      );

      // Update last snapshot month
      await prefs.setString(_lastSnapshotKey, currentMonth);

      print('✓ Monthly snapshot taken for $currentMonth');
    } catch (e) {
      print('Error taking snapshot: $e');
    }
  }

  /// Get last 6 months of snapshots — tries MongoDB first, then SharedPrefs cache.
  static Future<List<MonthlySnapshot>> getLast6Months({String userId = 'vikas@example.com'}) async {
    try {
      // ── Try MongoDB first ──────────────────────────────────────────────────
      final dbDocs = await DbService.fetchMonthlySnapshots(userId, count: 6);
      if (dbDocs.isNotEmpty) {
        return dbDocs.map((doc) => MonthlySnapshot(
          month:         doc['month']         as String? ?? '',
          essential:     (doc['essential']    as num?)?.toDouble() ?? 0,
          avoidable:     (doc['avoidable']    as num?)?.toDouble() ?? 0,
          impulse:       (doc['impulse']      as num?)?.toDouble() ?? 0,
          salary:        (doc['salary']       as num?)?.toDouble() ?? 0,
          nudgeSkips:    (doc['nudgeSkips']   as num?)?.toInt()    ?? 0,
          nudgeProceeds: (doc['nudgeProceeds'] as num?)?.toInt()   ?? 0,
        )).toList();
      }
    } catch (_) {}

    // ── Fallback: SharedPreferences cache ─────────────────────────────────
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      final snapshots = <MonthlySnapshot>[];
      for (int i = 0; i < 6; i++) {
        final date  = DateTime(now.year, now.month - i, 1);
        final month = '${date.year}-${date.month.toString().padLeft(2, '0')}';
        final json  = prefs.getString('snapshot_$month');
        if (json != null) {
          try {
            snapshots.add(MonthlySnapshot.fromJson(jsonDecode(json) as Map<String, dynamic>));
          } catch (_) {}
        }
      }
      snapshots.sort((a, b) => a.month.compareTo(b.month));
      return snapshots;
    } catch (e) {
      print('Error getting snapshots: $e');
      return [];
    }
  }

  static double _monthlyEquiv(double amount, String freq) {
    if (freq == 'daily') return amount * 30;
    if (freq == 'weekly') return amount * 52 / 12;
    return amount;
  }
}
