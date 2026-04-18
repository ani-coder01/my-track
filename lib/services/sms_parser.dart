import '../services/behavior_engine.dart';

class ParsedTransaction {
  final String merchant;
  final double amount;
  final DateTime datetime;

  ParsedTransaction({
    required this.merchant,
    required this.amount,
    required this.datetime,
  });
}

class SmsParser {
  // Indian bank SMS regex patterns
  static final _patterns = [
    /// HDFC: "debited for Rs 1,234 at Swiggy"
    RegExp(r'debited\s+for\s+Rs\s*[\.\,]?\s*([\d,\.]+)\s+at\s+(.+?)(?:\.|$)', caseSensitive: false),

    /// SBI: "debited with INR 1,234. Info: Swiggy"
    RegExp(r'debited\s+with\s+INR\s*([\d,\.]+).*?Info:\s*(.+?)(?:\.|$)', caseSensitive: false),

    /// ICICI: "Rs 1,234 debited from ... at Swiggy"
    RegExp(r'Rs\s*([\d,\.]+)\s+debited\s+from.*?at\s+(.+?)(?:\.|$)', caseSensitive: false),

    /// Paytm/UPI: "paid Rs 1,234 to Swiggy"
    RegExp(r'paid\s+Rs\s*[\.\,]?\s*([\d,\.]+)\s+to\s+(.+?)(?:\.|$)', caseSensitive: false),

    /// Generic UPI: "UPI transaction Rs 1,234 to Swiggy"
    RegExp(r'UPI.*?Rs\.?\s*([\d,\.]+).*?to\s+(.+?)(?:\.|$)', caseSensitive: false),

    /// Generic debit: "Rs 1,234 deducted from account"
    RegExp(r'Rs\s*([\d,\.]+)\s+(?:deducted|debited).*?(?:at|to|from)\s+(.+?)(?:\.|$)', caseSensitive: false),
  ];

  /// Parse SMS body and extract transaction details
  static ParsedTransaction? parse(String smsBody) {
    if (smsBody.isEmpty) return null;

    for (final pattern in _patterns) {
      final match = pattern.firstMatch(smsBody);
      if (match != null && match.groupCount >= 2) {
        try {
          final amountStr = match.group(1)!.replaceAll(',', '');
          final amount = double.parse(amountStr);
          final merchant = match.group(2)!.trim();

          if (amount > 0 && merchant.isNotEmpty) {
            return ParsedTransaction(
              merchant: merchant,
              amount: amount,
              datetime: DateTime.now(),
            );
          }
        } catch (_) {
          continue;
        }
      }
    }

    return null;
  }

  /// Find which watched app matches this merchant (fuzzy match)
  static String? fuzzyMatchWatchedApp(String merchant) {
    final merchantLower = merchant.toLowerCase();

    for (final entry in BehaviorEngine.watchedApps.entries) {
      final appName = entry.value.name.toLowerCase();
      if (merchantLower.contains(appName) || appName.contains(merchantLower)) {
        return entry.key;
      }
    }

    return null;
  }
}
