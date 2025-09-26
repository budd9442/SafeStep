package com.example.safestep

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
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
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import com.example.safestep.FakeCallUtils

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.safestep/fakecall"
    private val SOS_CHANNEL = "com.example.safestep/sos"
    private var alertVibrationHandler: Handler? = null
    private var alertVibrationRunnable: Runnable? = null
    private var stopAlertReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Existing channel for fakecall
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
                else -> result.notImplemented()
            }
        }
        // Add support for com.example.safestep/prefs channel for saveFakeCallPrefs
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.safestep/prefs").setMethodCallHandler { call, result ->
            when (call.method) {
                "saveFakeCallPrefs" -> {
                    val prefs = getSharedPreferences("fake_call_prefs", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putString("callerName", call.argument<String>("callerName"))
                        .putString("callerNumber", call.argument<String>("callerNumber"))
                        .putString("audioAsset", call.argument<String>("audioAsset"))
                        .apply()
                    result.success(null)
                }
                "saveUserMaxGesture" -> {
                    val maxGestureValue = call.argument<Double>("maxGestureValue")?.toFloat() ?: 0f
                    val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
                    prefs.edit().putFloat("user_max_gesture_value", maxGestureValue).apply()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Add SOS channel for opening SOS screen
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SOS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openSosScreen" -> {
                    // This will be handled by Flutter side
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Add shake gesture channel for recording gesture
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.safestep/shake_gesture").setMethodCallHandler { call, result ->
            when (call.method) {
                "recordShakeGesture" -> {
                    ShakeDetectionService.recordShakeGesture(this) { maxDelta, error ->
                        if (error != null) {
                            result.error("SENSOR_ERROR", error, null)
                        } else {
                            result.success(maxDelta)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // Remove notification permission request and notification listener settings
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Ensure screen can turn on and show over lock screen for SOS
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        // 1. Request location permission (all-time if possible)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                    android.Manifest.permission.ACCESS_COARSE_LOCATION,
                    android.Manifest.permission.ACCESS_BACKGROUND_LOCATION
                ), 1002
            )
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.ACCESS_FINE_LOCATION,
                    android.Manifest.permission.ACCESS_COARSE_LOCATION
                ), 1002
            )
        } else {
            // If below M, proceed to next step
            requestPhoneAccountPermissionAndSettings()
        }

        // Start DangerZoneService automatically
        val dangerZoneServiceIntent = Intent(this, DangerZoneService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(dangerZoneServiceIntent)
        } else {
            startService(dangerZoneServiceIntent)
        }

        val shakeIntent = intent
        val isShakeTrigger = shakeIntent?.action == "com.example.safestep.TRIGGER_FAKE_CALL"
        val isSosTrigger = shakeIntent?.action == "com.example.safestep.OPEN_SOS_SCREEN"
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
        
        // Handle SOS screen opening from gesture detection
        if (isSosTrigger) {
            // Store flag to open SOS screen when Flutter is ready
            val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
            prefs.edit().putBoolean("open_sos_screen", true).apply()
        }
    }

    private fun requestPhoneAccountPermissionAndSettings() {
        // 2. Request phone-related permissions if needed (e.g., READ_PHONE_STATE, CALL_PHONE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.READ_PHONE_STATE,
                    android.Manifest.permission.CALL_PHONE
                ), 1003
            )
        } else {
            // If below M, proceed to register phone account and open settings
            registerPhoneAccountAndOpenSettings()
        }
    }

    private fun registerPhoneAccountAndOpenSettings() {
        // Register as a caller (for fake call)
        val telecomManager = getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val componentName = ComponentName(this, FakeCallConnectionService::class.java)
        val phoneAccountHandle = PhoneAccountHandle(componentName, "SafeStepFakeCall")
        val phoneAccount = PhoneAccount.builder(phoneAccountHandle, "SafeStep Fake Call")
            .setCapabilities(PhoneAccount.CAPABILITY_CALL_PROVIDER)
            .setHighlightColor(Color.parseColor("#8F5FE8"))
            .build()
        telecomManager.registerPhoneAccount(phoneAccount)
        // Open the phone account settings UI
        val intent = Intent(TelecomManager.ACTION_CHANGE_PHONE_ACCOUNTS)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        startActivity(intent)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        // Remove notification permission handling
        if (requestCode == 1002) {
            if (grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                // Location permission granted, now request phone account permission and open settings
                requestPhoneAccountPermissionAndSettings()
            } else {
                android.widget.Toast.makeText(this, "Location permission is required for full functionality.", android.widget.Toast.LENGTH_LONG).show()
            }
        }
        if (requestCode == 1003) {
            if (grantResults.isNotEmpty() && grantResults[0] == android.content.pm.PackageManager.PERMISSION_GRANTED) {
                // Phone account permission granted, register phone account and open settings
                registerPhoneAccountAndOpenSettings()
            } else {
                android.widget.Toast.makeText(this, "Phone permissions are required for fake call feature.", android.widget.Toast.LENGTH_LONG).show()
            }
        }
    }
    
    override fun onResume() {
        super.onResume()
        // Check if we need to open SOS screen
        val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
        if (prefs.getBoolean("open_sos_screen", false)) {
            val messenger = flutterEngine?.dartExecutor?.binaryMessenger
            if (messenger != null) {
                MethodChannel(messenger, SOS_CHANNEL).invokeMethod("openSosScreen", null)
                // Clear the flag only after we successfully forwarded to Flutter
                prefs.edit().putBoolean("open_sos_screen", false).apply()
            } else {
                // Keep the flag; we'll try again on next resume when engine is ready
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val isSosTrigger = intent.action == "com.example.safestep.OPEN_SOS_SCREEN" || intent.getBooleanExtra("open_sos_screen", false)
        if (isSosTrigger) {
            // Ensure Flutter opens the SOS screen immediately if engine ready; otherwise set flag
            val messenger = flutterEngine?.dartExecutor?.binaryMessenger
            if (messenger != null) {
                MethodChannel(messenger, SOS_CHANNEL).invokeMethod("openSosScreen", null)
            } else {
                val prefs = getSharedPreferences("app_prefs", Context.MODE_PRIVATE)
                prefs.edit().putBoolean("open_sos_screen", true).apply()
            }
        }
    }
}
