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
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.safestep.FakeCallUtils

class ShakeDetectionService : Service(), SensorEventListener {
    private var userMaxGestureValue: Float = Float.POSITIVE_INFINITY
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
    // Allow multiple SOS triggers; rely on debounce timing instead of a sticky guard

    companion object {
    // Static method to record shake gesture for 10 seconds and return max value
        fun recordShakeGesture(context: Context, callback: (Float?, String?) -> Unit) {
            try {
                val sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
                val accelSensor = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                if (accelSensor == null) {
                    Log.e("ShakeDetectionService", "No accelerometer sensor available")
                    callback(null, "No accelerometer sensor available")
                    return
                }
                var accelLast = SensorManager.GRAVITY_EARTH
                var maxDelta = 0f
                val listener = object : SensorEventListener {
                    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                    override fun onSensorChanged(event: SensorEvent?) {
                        if (event?.sensor?.type == Sensor.TYPE_ACCELEROMETER) {
                            val x = event.values[0]
                            val y = event.values[1]
                            val z = event.values[2]
                            val accelCurrent = Math.sqrt((x * x + y * y + z * z).toDouble()).toFloat()
                            val delta = Math.abs(accelCurrent - accelLast)
                            accelLast = accelCurrent
                            if (delta > maxDelta) maxDelta = delta
                        }
                    }
                }
                sensorManager.registerListener(listener, accelSensor, SensorManager.SENSOR_DELAY_UI)
                android.os.Handler(context.mainLooper).postDelayed({
                    sensorManager.unregisterListener(listener)
                    Log.d("ShakeDetectionService", "Gesture recording finished, maxDelta=$maxDelta")
                    callback(maxDelta, null)
                }, 7000)
            } catch (e: Exception) {
                Log.e("ShakeDetectionService", "Error recording gesture: ${e.message}")
                callback(null, "Error recording gesture: ${e.message}")
            }
        }
    }

    override fun onCreate() {
        // Load user's recorded max gesture value from SharedPreferences
        val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
        if (prefs.contains("user_max_gesture_value")) {
            userMaxGestureValue = prefs.getFloat("user_max_gesture_value", Float.POSITIVE_INFINITY)
        } else {
            userMaxGestureValue = Float.POSITIVE_INFINITY
        }
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

            // Only show notification and send SOS if delta exceeds user's max gesture value
            if (delta > userMaxGestureValue && now - lastNotificationTime > NOTIFICATION_INTERVAL_MS) {
                lastNotificationTime = now
                showEventNotification(
                    "Maximum Gesture Exceeded",
                    "delta=%.2f exceeded user max %.2f".format(delta, userMaxGestureValue)
                )
                // Only trigger SOS if delta exceeds user's max
                if (now - shakeTimestamp > SHAKE_DEBOUNCE_MS) {
                    shakeTimestamp = now
                    openSosScreen()
                }
            }
        }
    }

    private fun onShakeDetected() {
        // Open SOS screen for every qualifying shake; SHAKE_DEBOUNCE_MS already prevents spam
        openSosScreen()
    }

    private fun openSosScreen() {
        try {
            // Persist flag; Flutter will open SOS once engine is ready (cold start safety)
            val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("open_sos_screen", true).apply()

            // Create intent to open/bring app to foreground with SOS screen
            val intent = Intent(applicationContext, MainActivity::class.java).apply {
                action = "com.example.safestep.OPEN_SOS_SCREEN"
                addCategory(Intent.CATEGORY_LAUNCHER)
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                putExtra("open_sos_screen", true)
                setPackage(packageName)
            }

            // Start the activity
            startActivity(intent)

            // Show notification that SOS screen was opened
            showEventNotification(
                "SOS Screen Opened",
                "Gesture detected - SOS screen opened"
            )
            
            Log.d("ShakeDetectionService", "SOS screen intent sent from background service")
        } catch (e: Exception) {
            Log.e("ShakeDetectionService", "Error opening SOS screen: ${e.message}")
            // Fallback: show notification
            showEventNotification(
                "Gesture Detected",
                "SOS screen could not be opened"
            )
        }
    }

    private val fakeCallActionReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            // No-op for multiple shake behavior
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
