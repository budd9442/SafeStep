package com.example.safestep

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.provider.Settings
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.graphics.Color
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import com.example.safestep.FakeCallUtils

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.safestep/fakecall"
    private val ALERT_CHANNEL_ID = "danger_zone_alert_channel"
    private val ALERT_NOTIFICATION_ID = 1001
    private var isAlerting = false
    private var alertVibrationHandler: Handler? = null
    private var alertVibrationRunnable: Runnable? = null
    private var stopAlertReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "triggerFakeCall" -> {
                    val callerName = call.argument<String>("callerName") ?: "Unknown"
                    val callerNumber = call.argument<String>("callerNumber") ?: "1234567890"
                    val audioPath = call.argument<String>("audioPath") ?: ""
                    FakeCallUtils.triggerFakeCall(this, callerName, callerNumber, audioPath)
                    result.success(null)
                }
                "saveFakeCallPrefs" -> {
                    val prefs = getSharedPreferences("fake_call_prefs", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putString("callerName", call.argument<String>("callerName"))
                        .putString("callerNumber", call.argument<String>("callerNumber"))
                        .putString("audioAsset", call.argument<String>("audioAsset"))
                        .apply()
                    result.success(null)
                }
                "startDangerZoneAlert" -> {
                    startDangerZoneAlert()
                    result.success(null)
                }
                "stopDangerZoneAlert" -> {
                    stopDangerZoneAlert()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun startDangerZoneAlert() {
        if (isAlerting) return
        isAlerting = true
        // Vibrate repeatedly
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        alertVibrationHandler = Handler(Looper.getMainLooper())
        alertVibrationRunnable = object : Runnable {
            override fun run() {
                if (isAlerting) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator.vibrate(VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE))
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(500)
                    }
                    alertVibrationHandler?.postDelayed(this, 1000)
                }
            }
        }
        alertVibrationHandler?.post(alertVibrationRunnable!!)
        showDangerZoneNotification()
        registerStopAlertReceiver()
    }

    private fun stopDangerZoneAlert() {
        isAlerting = false
        alertVibrationHandler?.removeCallbacks(alertVibrationRunnable!!)
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.cancel(ALERT_NOTIFICATION_ID)
        unregisterStopAlertReceiver()
    }

    private fun showDangerZoneNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(ALERT_CHANNEL_ID, "Danger Zone Alerts", NotificationManager.IMPORTANCE_HIGH)
            channel.description = "Alerts when you are in a danger zone"
            notificationManager.createNotificationChannel(channel)
        }
        val stopIntent = Intent("com.example.safestep.STOP_ALERT")
        val stopPendingIntent = PendingIntent.getBroadcast(this, 0, stopIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = Notification.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle("Danger Zone Alert")
            .setContentText("You are in a danger zone! Tap to stop alerting.")
            .setSmallIcon(android.R.drawable.ic_dialog_alert)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, "Stop Alerting", stopPendingIntent).build())
            .build()
        notificationManager.notify(ALERT_NOTIFICATION_ID, notification)
    }

    private fun registerStopAlertReceiver() {
        if (stopAlertReceiver != null) return
        stopAlertReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                stopDangerZoneAlert()
            }
        }
        registerReceiver(stopAlertReceiver, IntentFilter("com.example.safestep.STOP_ALERT"))
    }

    private fun unregisterStopAlertReceiver() {
        if (stopAlertReceiver != null) {
            unregisterReceiver(stopAlertReceiver)
            stopAlertReceiver = null
        }
    }

    override fun onDestroy() {
        stopDangerZoneAlert()
        super.onDestroy()
    }

    // Start ShakeDetectionService from Flutter
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Start DangerZoneService automatically
        val dangerZoneServiceIntent = Intent(this, DangerZoneService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(dangerZoneServiceIntent)
        } else {
            startService(dangerZoneServiceIntent)
        }

        val shakeIntent = intent
        val isShakeTrigger = shakeIntent?.action == "com.example.safestep.TRIGGER_FAKE_CALL"
        val startShakeServiceIntent = Intent(this, ShakeDetectionService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(startShakeServiceIntent)
        } else {
            startService(startShakeServiceIntent)
        }

        // Listen for shake-triggered fake call
        if (isShakeTrigger) {
            // Load last-used values from SharedPreferences
            val prefs = getSharedPreferences("fake_call_prefs", Context.MODE_PRIVATE)
            val callerName = prefs.getString("callerName", "Unknown") ?: "Unknown"
            val callerNumber = prefs.getString("callerNumber", "1234567890") ?: "1234567890"
            val audioAsset = prefs.getString("audioAsset", "") ?: ""
            val audioPath = audioAsset
            FakeCallUtils.triggerFakeCall(this, callerName, callerNumber, audioPath)
            finish()
            return
        }
    }
}
