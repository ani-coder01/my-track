package com.example.expense_autopsy

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

class AppMonitorService : Service() {

    companion object {
        const val CHANNEL_ID   = "expense_autopsy_monitor"
        const val NOTIF_ID     = 1001
        const val ACTION_START = "START_MONITOR"
        const val ACTION_STOP  = "STOP_MONITOR"

        // Spending apps to watch
        val WATCHED_APPS = mapOf(
            "com.application.zomato"                    to "Zomato",
            "in.swiggy.android"                         to "Swiggy",
            "com.grofers.customerapp"                   to "Blinkit",
            "com.zeptconsumerapp"                       to "Zepto",
            "com.amazon.mShop.android.shopping"         to "Amazon",
            "com.flipkart.android"                      to "Flipkart",
            "com.myntra.android"                        to "Myntra",
            "com.ril.ajio"                              to "Ajio",
            "com.fsn.nykaa"                             to "Nykaa",
            "com.bms.bmsapp"                            to "BookMyShow",
            "com.bigbasket.mobileapp"                   to "BigBasket",
            "com.phonepe.app"                           to "PhonePe",
            "net.one97.paytm"                           to "Paytm",
            "com.google.android.apps.nbu.paisa.user"    to "Google Pay",
        )

        // Shared event sink — set by the plugin
        var eventSink: io.flutter.plugin.common.EventChannel.EventSink? = null
    }

    private val handler  = Handler(Looper.getMainLooper())
    private var lastApp  = ""
    private var running  = false

    private val pollingRunnable = object : Runnable {
        override fun run() {
            if (!running) return
            checkForegroundApp()
            handler.postDelayed(this, 1500) // poll every 1.5 seconds
        }
    }

    // ── Lifecycle ─────────────────────────────────────────────────────────

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())

        if (intent?.action != ACTION_STOP) {
            running = true
            handler.post(pollingRunnable)
        } else {
            stopSelf()
        }
        return START_STICKY
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacks(pollingRunnable)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Core polling ──────────────────────────────────────────────────────

    private fun checkForegroundApp() {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val now  = System.currentTimeMillis()
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_DAILY,
            now - 1_000 * 60 * 60, // last 1 hour window
            now
        ) ?: return

        val topApp = stats
            .filter { it.lastTimeUsed > 0 }
            .maxByOrNull { it.lastTimeUsed }
            ?.packageName ?: return

        if (topApp != lastApp) {
            lastApp = topApp
            val appName = WATCHED_APPS[topApp]
            if (appName != null) {
                // Bring Expense Autopsy to the foreground over the watched app
                val intent = Intent(this, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                startActivity(intent)

                // Fire event to Flutter
                val payload = mapOf(
                    "package"   to topApp,
                    "app"       to appName,
                    "timestamp" to now
                )
                handler.post {
                    eventSink?.success(payload)
                }
            }
        }
    }

    // ── Notification ──────────────────────────────────────────────────────

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Spending Monitor",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Watching for impulsive spending app opens"
            setShowBadge(false)
        }
        val nm = getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Expense Autopsy")
            .setContentText("Watching for spending traps 🛡️")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }
}
