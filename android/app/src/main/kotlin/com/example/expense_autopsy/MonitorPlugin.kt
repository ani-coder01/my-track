package com.example.expense_autopsy

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MonitorPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "expense_autopsy/monitor"
        const val EVENT_CHANNEL  = "expense_autopsy/monitor_events"

        fun register(flutterEngine: FlutterEngine, context: Context) {
            val plugin = MonitorPlugin(context)

            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                METHOD_CHANNEL
            ).setMethodCallHandler(plugin)

            EventChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                EVENT_CHANNEL
            ).setStreamHandler(plugin)
        }
    }

    // ── MethodChannel ─────────────────────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {

            "checkUsagePermission" -> {
                result.success(hasUsagePermission())
            }

            "requestUsagePermission" -> {
                val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
                result.success(null)
            }

            "checkOverlayPermission" -> {
                result.success(Settings.canDrawOverlays(context))
            }

            "requestOverlayPermission" -> {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${context.packageName}")
                ).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK }
                context.startActivity(intent)
                result.success(null)
            }

            "startMonitor" -> {
                val intent = Intent(context, AppMonitorService::class.java).apply {
                    action = AppMonitorService.ACTION_START
                }
                context.startForegroundService(intent)
                result.success(true)
            }

            "stopMonitor" -> {
                val intent = Intent(context, AppMonitorService::class.java).apply {
                    action = AppMonitorService.ACTION_STOP
                }
                context.startService(intent)
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    // ── EventChannel (app-open stream) ────────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        AppMonitorService.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        AppMonitorService.eventSink = null
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private fun hasUsagePermission(): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode   = appOps.unsafeCheckOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            android.os.Process.myUid(),
            context.packageName
        )
        return mode == AppOpsManager.MODE_ALLOWED
    }
}
