package com.example.safestep

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
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
                else -> result.notImplemented()
            }
        }
    }

    // Start ShakeDetectionService from Flutter
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
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
