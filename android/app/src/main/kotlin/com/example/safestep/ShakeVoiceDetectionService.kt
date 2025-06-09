package com.example.safestep

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.example.safestep.FakeCallUtils

class ShakeDetectionService : Service(), SensorEventListener {
    private lateinit var sensorManager: SensorManager
    private var accelLast = 0f
    private var shakeTimestamp: Long = 0
    private val SHAKE_MAGNITUDE_THRESHOLD = 13f
    private val SHAKE_DEBOUNCE_MS = 2000L
    private val CHANNEL_ID = "shake_detection_service"
    private val NOTIFICATION_ID = 2001
    private var lastNotificationTime = 0L
    private val NOTIFICATION_INTERVAL_MS = 2000L
    private val DELTA_HISTORY_SIZE = 10
    private val deltaHistory = FloatArray(DELTA_HISTORY_SIZE)
    private val deltaTimeHistory = LongArray(DELTA_HISTORY_SIZE)
    private var deltaHistoryIndex = 0
    private var isFakeCallActive = false

    override fun onCreate() {
        super.onCreate()
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val accelSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        sensorManager.registerListener(this, accelSensor, SensorManager.SENSOR_DELAY_UI)
        accelLast = SensorManager.GRAVITY_EARTH
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification("Shake detection active"))
        val filter = android.content.IntentFilter().apply {
            addAction("com.example.safestep.FAKE_CALL_ACCEPTED")
            addAction("com.example.safestep.FAKE_CALL_REJECTED")
        }
        registerReceiver(fakeCallActionReceiver, filter)
    }

    override fun onDestroy() {
        super.onDestroy()
        sensorManager.unregisterListener(this)
        unregisterReceiver(fakeCallActionReceiver)
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_ACCELEROMETER) {
            val x = event.values[0]
            val y = event.values[1]
            val z = event.values[2]
            val accelCurrent = Math.sqrt((x * x + y * y + z * z).toDouble()).toFloat()
            val delta = Math.abs(accelCurrent - accelLast)
            accelLast = accelCurrent
            val now = System.currentTimeMillis()
            deltaHistory[deltaHistoryIndex] = delta
            deltaTimeHistory[deltaHistoryIndex] = now
            deltaHistoryIndex = (deltaHistoryIndex + 1) % DELTA_HISTORY_SIZE
            if (delta > 4f && now - lastNotificationTime > NOTIFICATION_INTERVAL_MS) {
                lastNotificationTime = now
                showEventNotification(
                    "Shake detection active",
                    "delta=%.2f, thresh=4.5".format(delta)
                )
            }
            var count = 0
            for (i in 0 until DELTA_HISTORY_SIZE) {
                if (now - deltaTimeHistory[i] <= 1500L && deltaHistory[i] > 4.5f) {
                    count++
                }
            }
            if (count >= 2 && delta > 4.5f) {
                if (now - shakeTimestamp > SHAKE_DEBOUNCE_MS) {
                    shakeTimestamp = now
                    onShakeDetected()
                }
            }
        }
    }

    private fun onShakeDetected() {
        if (!isFakeCallActive) {
            isFakeCallActive = true
            val prefs = getSharedPreferences("fake_call_prefs", Context.MODE_PRIVATE)
            val callerName = prefs.getString("callerName", "Unknown") ?: "Unknown"
            val callerNumber = prefs.getString("callerNumber", "1234567890") ?: "1234567890"
            val audioAsset = prefs.getString("audioAsset", "") ?: ""
            val audioPath = audioAsset
            FakeCallUtils.triggerFakeCall(applicationContext, callerName, callerNumber, audioPath)
        }
    }

    private val fakeCallActionReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "com.example.safestep.FAKE_CALL_ACCEPTED" || intent?.action == "com.example.safestep.FAKE_CALL_REJECTED") {
                isFakeCallActive = false
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Shake Detection",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(content: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SafeStep Background Detection")
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .build()
    }

    private fun showEventNotification(title: String, content: String) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setAutoCancel(true)
            .build()
        manager.notify((System.currentTimeMillis() % 10000).toInt(), notification)
    }
}
