import 'package:mongo_dart/mongo_dart.dart';
import 'package:flutter/foundation.dart';

class DbService {
  static const String _uri =
      'mongodb+srv://nickhasntlost_db_user:Pz03WjAzQ8pv7ygA@cluster0.mgoqoor.mongodb.net/expense_app?retryWrites=true&w=majority&appName=Cluster0';

  static Db? _db;

  static Future<void> connect() async {
    try {
      _db = await Db.create(_uri);
      await _db!.open();
      if (kDebugMode) print('✅ Connected to MongoDB');
    } catch (e) {
      if (kDebugMode) print('❌ MongoDB connect error: $e');
    }
  }

  static Future<void> _ensureConnected() async {
    if (_db == null || !_db!.isConnected) await connect();
  }

  // ── User profile ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> fetchUserData(String email) async {
    await _ensureConnected();
    if (_db == null || !_db!.isConnected) return null;
    try {
      final collection = _db!.collection('users');
      return await collection.findOne(where.eq('email', email));
    } catch (e) {
      if (kDebugMode) print('fetchUserData error: $e');
      return null;
    }
  }

  // ── Update profile ────────────────────────────────────────────────────────

  /// Persist updated profile + sip fields back to MongoDB for `email`.
  static Future<bool> updateUserProfile(
    String email, {
    required String name,
    required double monthlySalary,
    required double sipAmount,
    required double sipReturn,
    required int sipMonths,
    String? occupation,
    String? city,
  }) async {
    await _ensureConnected();
    if (_db == null || !_db!.isConnected) return false;
    try {
      final collection = _db!.collection('users');
      await collection.updateOne(
        where.eq('email', email),
        modify
            .set('profile.name',          name)
            .set('profile.monthlySalary', monthlySalary)
            .set('sip.monthlyAmount',     sipAmount)
            .set('sip.annualReturn',      sipReturn)
            .set('sip.durationMonths',    sipMonths)
            ..set('profile.occupation',   occupation ?? '')
            ..set('profile.city',         city ?? ''),
        upsert: true,
      );
      if (kDebugMode) print('✅ Profile updated in MongoDB');
      return true;
    } catch (e) {
      if (kDebugMode) print('updateUserProfile error: $e');
      return false;
    }
  }

  // ── Expenses ──────────────────────────────────────────────────────────────

  /// Fetch all expenses for a user from the `expenses` collection.
  static Future<List<Map<String, dynamic>>> fetchUserExpenses(String userId) async {
    await _ensureConnected();
    if (_db == null || !_db!.isConnected) return [];
    try {
      final collection = _db!.collection('expenses');
      final docs = await collection.find(where.eq('userId', userId)).toList();
      return docs.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('fetchUserExpenses error: $e');
      return [];
    }
  }

  // ── Goals ─────────────────────────────────────────────────────────────────

  /// Fetch all goals for a user from the `goals` collection.
  static Future<List<Map<String, dynamic>>> fetchUserGoals(String userId) async {
    await _ensureConnected();
    if (_db == null || !_db!.isConnected) return [];
    try {
      final collection = _db!.collection('goals');
      final docs = await collection.find(where.eq('userId', userId)).toList();
      return docs.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('fetchUserGoals error: $e');
      return [];
    }
  }

  // ── Monthly Snapshots ─────────────────────────────────────────────────────

  /// Fetch last N monthly snapshots for a user from `monthly_snapshots`.
  static Future<List<Map<String, dynamic>>> fetchMonthlySnapshots(
    String userId, {
    int count = 6,
  }) async {
    await _ensureConnected();
    if (_db == null || !_db!.isConnected) return [];
    try {
      final collection = _db!.collection('monthly_snapshots');
      final docs = await collection
          .find(where.eq('userId', userId).sortBy('month', descending: true).limit(count))
          .toList();
      // Sort oldest-first
      docs.sort((a, b) => (a['month'] as String).compareTo(b['month'] as String));
      return docs.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('fetchMonthlySnapshots error: $e');
      return [];
    }
  }

  // ── Behavior events ───────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchBehaviorEvents(
    String userId, {
    int daysBack = 30,
  }) async {
    await _ensureConnected();
    if (_db == null || !_db!.isConnected) return [];
    try {
      final collection = _db!.collection('behavior_events');
      final cutoff = DateTime.now().subtract(Duration(days: daysBack));
      final events = await collection
          .find(where.eq('userId', userId).gte('timestamp', cutoff))
          .toList();
      return events.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) print('fetchBehaviorEvents error: $e');
      return [];
    }
  }

  static Future<int> countSkippedDecisions(String userId, {int daysBack = 30}) async {
    final events = await fetchBehaviorEvents(userId, daysBack: daysBack);
    return events.where((e) => e['decision'] == 'skipped').length;
  }

  static void close() {
    _db?.close();
  }
}
