package com.example.safestep

import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.graphics.Color

object FakeCallUtils {
    @JvmStatic
    fun triggerFakeCall(context: Context, callerName: String, callerNumber: String, audioPath: String) {
        val telecomManager = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager
        val handle = PhoneAccountHandle(
            ComponentName(context, FakeCallConnectionService::class.java),
            "fake_call_account"
        )
        // Register phone account if needed
        if (telecomManager.getPhoneAccount(handle) == null) {
            val account = PhoneAccount.builder(handle, "Fake Call")
                .setCapabilities(PhoneAccount.CAPABILITY_CALL_PROVIDER)
                .setHighlightColor(Color.GREEN)
                .build()
            telecomManager.registerPhoneAccount(account)
        }
        // Check if enabled
        val account = telecomManager.getPhoneAccount(handle)
        if (account == null || !account.isEnabled) {
            // Optionally prompt user to enable
            return
        }
        val extras = Bundle()
        extras.putParcelable(TelecomManager.EXTRA_INCOMING_CALL_ADDRESS, android.net.Uri.fromParts("tel", callerNumber, null))
        extras.putString("callerName", callerName)
        extras.putString("audioPath", audioPath)
        telecomManager.addNewIncomingCall(handle, extras)
    }
}
