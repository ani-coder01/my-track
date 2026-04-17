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
      if (kDebugMode) {
        print('Connected to MongoDB!');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error connecting to MongoDB: $e');
      }
    }
  }

  static Future<Map<String, dynamic>?> fetchUserData(String email) async {
    if (_db == null || !_db!.isConnected) {
      await connect();
    }

    if (_db == null || !_db!.isConnected) {
      return null; // Still failed to connect
    }

    try {
      final collection = _db!.collection('users');
      final user = await collection.findOne(where.eq('email', email));
      return user;
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching user data: $e');
      }
      return null;
    }
  }

  /// Fetch behavior events for a user (last 30 days)
  static Future<List<Map<String, dynamic>>> fetchBehaviorEvents(String userId, {int daysBack = 30}) async {
    if (_db == null || !_db!.isConnected) {
      await connect();
    }

    if (_db == null || !_db!.isConnected) {
      return [];
    }

    try {
      final collection = _db!.collection('behavior_events');
      final thirtyDaysAgo = DateTime.now().subtract(Duration(days: daysBack));

      final events = await collection
          .find(where.eq('userId', userId).gte('timestamp', thirtyDaysAgo))
          .toList();

      return events.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching behavior events: $e');
      }
      return [];
    }
  }

  /// Count skipped decisions in the last N days
  static Future<int> countSkippedDecisions(String userId, {int daysBack = 30}) async {
    final events = await fetchBehaviorEvents(userId, daysBack: daysBack);
    return events.where((e) => e['decision'] == 'skipped').length;
  }

  /// Calculate total saved from skipped decisions
  static Future<double> calculateTotalSaved(String userId) async {
    final events = await fetchBehaviorEvents(userId, daysBack: 365);

    // Estimate savings: each skip saves ~60-70% of avg spend
    double totalSaved = 0;
    for (final event in events) {
      if (event['decision'] == 'skipped') {
        final appName = event['appName'] as String? ?? '';
        // Estimate avg spend based on app (simplified)
        double estSpend = 500;
        if (appName.contains('Zomato') || appName.contains('Swiggy')) estSpend = 350;
        else if (appName.contains('Amazon')) estSpend = 1200;
        else if (appName.contains('Flipkart')) estSpend = 900;

        totalSaved += estSpend * 0.65; // Save ~65% when skipped
      }
    }

    return totalSaved;
  }

  /// Get 6-month income chart data (simulated with slight variations)
  static Future<List<double>> getFakeSixMonthIncomeData(double salary) async {
    // Return last 6 months with ±2% variation to simulate real data
    return [0.98, 0.99, 1.00, 0.99, 1.01, 1.00]
        .map((factor) => salary * factor)
        .toList();
  }

  /// Get user goals
  static Future<List<Map<String, dynamic>>> fetchUserGoals(String userId) async {
    if (_db == null || !_db!.isConnected) {
      await connect();
    }

    if (_db == null || !_db!.isConnected) {
      return [];
    }

    try {
      final collection = _db!.collection('goals');
      final goals = await collection
          .find(where.eq('userId', userId))
          .toList();

      return goals.cast<Map<String, dynamic>>();
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching goals: $e');
      }
      return [];
    }
  }

  static void close() {
    _db?.close();
  }
}

