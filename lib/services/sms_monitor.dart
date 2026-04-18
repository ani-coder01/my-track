import 'dart:async';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';
import 'sms_parser.dart';

class SmsMonitor {
  static final Telephony _telephony = Telephony.instance;
  static final _streamController = StreamController<ParsedTransaction>.broadcast();

  static Stream<ParsedTransaction> get stream => _streamController.stream;

  /// Initialize SMS monitoring
  static Future<void> init() async {
    try {
      // Request SMS permission
      final status = await Permission.sms.request();
      if (!status.isGranted) {
        print('SMS permission denied');
        return;
      }

      // Start listening for incoming SMS
      _telephony.listenIncomingSms(
        onNewMessage: (SmsMessage message) {
          if (message.body != null) {
            final parsed = SmsParser.parse(message.body!);
            if (parsed != null) {
              _streamController.add(parsed);
            }
          }
        },
        listenInBackground: false,
      );

      print('SMS Monitor initialized');
    } catch (e) {
      print('Error initializing SMS monitor: $e');
    }
  }

  /// Scan recent SMS from the last N days
  static Future<List<ParsedTransaction>> scanRecent({int days = 7}) async {
    try {
      final status = await Permission.sms.request();
      if (!status.isGranted) {
        return [];
      }

      final List<SmsMessage> messages = await _telephony.getInboxSms() ?? [];
      final cutoffDate = DateTime.now().subtract(Duration(days: days));

      final List<ParsedTransaction> transactions = [];

      for (final message in messages) {
        if (message.date != null) {
          final messageDate = DateTime.fromMillisecondsSinceEpoch(message.date!);
          if (messageDate.isAfter(cutoffDate) && message.body != null) {
            final parsed = SmsParser.parse(message.body!);
            if (parsed != null) {
              transactions.add(parsed);
            }
          }
        }
      }

      return transactions;
    } catch (e) {
      print('Error scanning recent SMS: $e');
      return [];
    }
  }

  static void dispose() {
    _streamController.close();
  }
}
