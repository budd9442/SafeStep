package com.example.safestep

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.provider.Settings
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.graphics.Color
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterActivity
import android.content.IntentFilter

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.safestep/fakecall"
    private val POWER_CHANNEL = "com.example.safestep/powerbutton"
    private var powerButtonMethodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "triggerFakeCall") {
                val callerName = call.argument<String>("callerName") ?: "Unknown"
                val callerNumber = call.argument<String>("callerNumber") ?: "1234567890"
                val audioPath = call.argument<String>("audioPath") ?: ""
                triggerFakeCall(this, callerName, callerNumber, audioPath)
                result.success(null)
            }
        }
        powerButtonMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, POWER_CHANNEL)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Start VolumeButtonService for background volume button detection
        val serviceIntent = Intent(this, VolumeButtonService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }
        // Handle intent if app is launched from service
        if (intent?.getBooleanExtra("trigger_fake_call", false) == true) {
            powerButtonMethodChannel?.invokeMethod("triggerFakeCallFromNative", null)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("trigger_fake_call", false)) {
            powerButtonMethodChannel?.invokeMethod("triggerFakeCallFromNative", null)
        }
    }

    private fun registerFakePhoneAccount(context: Context) {
        val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val handle = PhoneAccountHandle(
            ComponentName(context, FakeCallConnectionService::class.java),
            "fake_call_account"
        )
        val account = PhoneAccount.builder(handle, "Fake Call")
            .setCapabilities(PhoneAccount.CAPABILITY_CALL_PROVIDER)
            .setHighlightColor(Color.GREEN)
            .build()
        telecomManager.registerPhoneAccount(account)
    }

    private fun promptEnablePhoneAccount(context: Context) {
        val intent = Intent(TelecomManager.ACTION_CHANGE_PHONE_ACCOUNTS)
        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
        context.startActivity(intent)
    }

    private fun isPhoneAccountEnabled(context: Context): Boolean {
        val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val handle = PhoneAccountHandle(
            ComponentName(context, FakeCallConnectionService::class.java),
            "fake_call_account"
        )
        val account = telecomManager.getPhoneAccount(handle)
        return account != null && account.isEnabled
    }

    private fun triggerFakeCall(context: Context, callerName: String, callerNumber: String, audioPath: String) {
        registerFakePhoneAccount(context)
        if (!isPhoneAccountEnabled(context)) {
            promptEnablePhoneAccount(context)
            return
        }
        val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val handle = PhoneAccountHandle(
            ComponentName(context, FakeCallConnectionService::class.java),
            "fake_call_account"
        )
        val extras = Bundle()
        extras.putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, android.net.Uri.fromParts("tel", callerNumber, null))
        extras.putString("callerName", callerName)
        extras.putString("audioPath", audioPath)
        telecomManager.addNewIncomingCall(handle, extras)
    }
}
