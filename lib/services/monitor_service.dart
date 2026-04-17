// lib/services/monitor_service.dart
//
// Flutter ↔ Android bridge for the app-usage monitor.
// Wraps the MethodChannel + EventChannel exposed by MonitorPlugin.kt

import 'package:flutter/services.dart';

typedef AppOpenCallback = void Function(String packageName, String appName);

class MonitorService {
  static const _method = MethodChannel('expense_autopsy/monitor');
  static const _events = EventChannel('expense_autopsy/monitor_events');

  static AppOpenCallback? _onAppOpen;
  static bool _listening = false;

  // ── Permission helpers ─────────────────────────────────────────────────

  static Future<bool> hasUsagePermission() async {
    return await _method.invokeMethod<bool>('checkUsagePermission') ?? false;
  }

  static Future<void> requestUsagePermission() async {
    await _method.invokeMethod('requestUsagePermission');
  }

  static Future<bool> hasOverlayPermission() async {
    return await _method.invokeMethod<bool>('checkOverlayPermission') ?? false;
  }

  static Future<void> requestOverlayPermission() async {
    await _method.invokeMethod('requestOverlayPermission');
  }

  // ── Service control ────────────────────────────────────────────────────

  static Future<void> startMonitor() async {
    await _method.invokeMethod('startMonitor');
    _startListening();
  }

  static Future<void> stopMonitor() async {
    await _method.invokeMethod('stopMonitor');
  }

  // ── Event stream ───────────────────────────────────────────────────────

  static void setOnAppOpen(AppOpenCallback callback) {
    _onAppOpen = callback;
    if (!_listening) _startListening();
  }

  static void _startListening() {
    if (_listening) return;
    _listening = true;

    _events.receiveBroadcastStream().listen((dynamic event) {
      if (event is Map) {
        final pkg  = event['package']  as String? ?? '';
        final name = event['app']      as String? ?? pkg;
        _onAppOpen?.call(pkg, name);
      }
    }, onError: (e) {
      _listening = false;
    });
  }
}
