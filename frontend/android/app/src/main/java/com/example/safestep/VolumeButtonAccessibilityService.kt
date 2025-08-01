package com.example.safestep

import android.accessibilityservice.AccessibilityService
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.content.Intent
import android.widget.Toast

class VolumeButtonAccessibilityService : AccessibilityService() {
    override fun onServiceConnected() {
        super.onServiceConnected()
        Log.d("SafeStepDebug", "AccessibilityService: onServiceConnected")
        Toast.makeText(this, "SafeStep AccessibilityService connected", Toast.LENGTH_SHORT).show()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        Log.d("SafeStepDebug", "AccessibilityService: onUnbind")
        return super.onUnbind(intent)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not used
        Log.d("SafeStepDebug", "AccessibilityService: onAccessibilityEvent: $event")
    }

    override fun onInterrupt() {
        Log.d("SafeStepDebug", "AccessibilityService: onInterrupt")
    }
}
