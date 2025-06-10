package com.example.safestep

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.annotation.Nullable
import androidx.core.app.ActivityCompat
import com.google.android.gms.location.*
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.QuerySnapshot
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

class DangerZoneService : Service() {
    private val ALERT_CHANNEL_ID = "danger_zone_alert_channel"
    private val ALERT_NOTIFICATION_ID = 1002
    private var isAlerting = false
    private var handler: Handler? = null
    private var runnable: Runnable? = null
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var stopAlertReceiver: BroadcastReceiver? = null
    private var lastDangerZoneId: String? = null
    private var vibrationSuppressedForZone: String? = null
    private var dangerZonesSnapshot: QuerySnapshot? = null
    private var dangerZonesListener: com.google.firebase.firestore.ListenerRegistration? = null

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        handler = Handler(Looper.getMainLooper())
        startForeground(ALERT_NOTIFICATION_ID, buildNotification("Monitoring for danger zones..."))
        startDangerZonesRealtimeListener()
        startRepeatingCheck()
        registerStopAlertReceiver()
    }

    private fun startDangerZonesRealtimeListener() {
        dangerZonesListener = FirebaseFirestore.getInstance().collection("dangerzones")
            .addSnapshotListener { snapshot, _ ->
                if (snapshot != null) {
                    dangerZonesSnapshot = snapshot
                    // Immediately re-check location against updated danger zones
                    if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED ||
                        ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                        fusedLocationClient?.lastLocation?.addOnSuccessListener { location: Location? ->
                            if (location != null) {
                                checkLocationAgainstDangerZones(location)
                            }
                        }
                    }
                }
            }
    }

    private fun stopDangerZonesRealtimeListener() {
        dangerZonesListener?.remove()
        dangerZonesListener = null
        dangerZonesSnapshot = null
    }

    private fun startRepeatingCheck() {
        runnable = object : Runnable {
            override fun run() {
                checkDangerZones()
                handler?.postDelayed(this, TimeUnit.SECONDS.toMillis(10))
            }
        }
        handler?.post(runnable!!)
    }

    private fun checkDangerZones() {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != android.content.pm.PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != android.content.pm.PackageManager.PERMISSION_GRANTED) {
            // Permissions not granted
            return
        }
        fusedLocationClient?.lastLocation?.addOnSuccessListener { location: Location? ->
            if (location != null) {
                checkLocationAgainstDangerZones(location)
            }
        }
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
        startForeground(ALERT_NOTIFICATION_ID, notification)
    }

    private fun updateMonitoringNotification() {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification = buildNotification("Monitoring for danger zones...")
        notificationManager.notify(ALERT_NOTIFICATION_ID, notification)
        startForeground(ALERT_NOTIFICATION_ID, notification)
    }

    private fun updateNotificationState(inZone: Boolean) {
        if (inZone) {
            showDangerZoneNotification()
        } else {
            updateMonitoringNotification()
        }
    }

    private fun checkLocationAgainstDangerZones(location: Location) {
        val snapshot = dangerZonesSnapshot ?: return
        var inZone = false
        var zoneId: String? = null
        for (doc in snapshot.documents) {
            val lat = doc.getDouble("lat") ?: continue
            val lng = doc.getDouble("lng") ?: continue
            val radius = doc.getDouble("radius") ?: 0.0
            val zoneLocation = Location("")
            zoneLocation.latitude = lat
            zoneLocation.longitude = lng
            val distance = location.distanceTo(zoneLocation)
            if (distance <= radius) {
                inZone = true
                zoneId = doc.id
                break
            }
        }
        updateNotificationState(inZone)
        if (inZone && lastDangerZoneId != zoneId) {
            lastDangerZoneId = zoneId
            vibrationSuppressedForZone = null // reset suppression for new zone
            startDangerZoneAlert(zoneId)
        } else if (!inZone) {
            lastDangerZoneId = null
            vibrationSuppressedForZone = null
            stopDangerZoneAlert(keepNotification = true)
        }
    }

    private fun startDangerZoneAlert(zoneId: String?) {
        if (isAlerting && vibrationSuppressedForZone == zoneId) return
        isAlerting = true
        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        handler?.post(object : Runnable {
            override fun run() {
                if (isAlerting && vibrationSuppressedForZone != zoneId) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator.vibrate(VibrationEffect.createOneShot(500, VibrationEffect.DEFAULT_AMPLITUDE))
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(500)
                    }
                    handler?.postDelayed(this, 1000)
                }
            }
        })
        showDangerZoneNotification()
    }

    private fun stopDangerZoneAlert(keepNotification: Boolean = false) {
        isAlerting = false
        handler?.removeCallbacksAndMessages(null)
        if (!keepNotification) {
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(ALERT_NOTIFICATION_ID)
            // Restart foreground notification for monitoring
            startForeground(ALERT_NOTIFICATION_ID, buildNotification("Monitoring for danger zones..."))
        }
    }

    private fun buildNotification(content: String): Notification {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(ALERT_CHANNEL_ID, "Danger Zone Alerts", NotificationManager.IMPORTANCE_LOW)
            channel.description = "Alerts when you are in a danger zone"
            notificationManager.createNotificationChannel(channel)
        }
        return Notification.Builder(this, ALERT_CHANNEL_ID)
            .setContentTitle("SafeStep")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .build()
    }

    private fun registerStopAlertReceiver() {
        if (stopAlertReceiver != null) return
        stopAlertReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                vibrationSuppressedForZone = lastDangerZoneId
                handler?.removeCallbacksAndMessages(null)
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
        unregisterStopAlertReceiver()
        handler?.removeCallbacksAndMessages(null)
        stopDangerZonesRealtimeListener()
        super.onDestroy()
    }

    @Nullable
    override fun onBind(intent: Intent?): IBinder? = null
}
