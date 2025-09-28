package com.example.safestep

import android.content.Intent
import android.content.SharedPreferences
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log

class FakeCallQuickTileService : TileService() {
    
    override fun onCreate() {
        super.onCreate()
        Log.d("FakeCallQuickTile", "Service created")
    }
    
    override fun onStartListening() {
        super.onStartListening()
        Log.d("FakeCallQuickTile", "Started listening")
        updateTile()
    }
    
    override fun onStopListening() {
        super.onStopListening()
        Log.d("FakeCallQuickTile", "Stopped listening")
    }
    
    override fun onClick() {
        super.onClick()
        Log.d("FakeCallQuickTile", "Tile clicked")
        triggerFakeCall()
    }
    
    private fun updateTile() {
        val tile = qsTile
        if (tile != null) {
            Log.d("FakeCallQuickTile", "Updating tile")
            
            // Always available - use SafeStep as default if not configured
            tile.state = Tile.STATE_INACTIVE  // Available but not currently active
            tile.label = "Fake Call"
            tile.contentDescription = "Trigger fake call"
            tile.updateTile()
            
            Log.d("FakeCallQuickTile", "Tile updated successfully")
        } else {
            Log.e("FakeCallQuickTile", "Tile is null")
        }
    }
    
    private fun triggerFakeCall() {
        try {
            Log.d("FakeCallQuickTile", "Triggering fake call")
            
            // Load saved preferences, use SafeStep as default if not configured
            val prefs = getSharedPreferences("fake_call_prefs", MODE_PRIVATE)
            val callerName = prefs.getString("callerName", "")?.takeIf { it.isNotEmpty() } ?: "SafeStep"
            val callerNumber = prefs.getString("callerNumber", "")?.takeIf { it.isNotEmpty() } ?: "1234567890"
            val audioAsset = prefs.getString("audioAsset", "") ?: ""
            
            Log.d("FakeCallQuickTile", "Triggering fake call: $callerName ($callerNumber)")
            
            // Trigger fake call using the existing utility
            FakeCallUtils.triggerFakeCall(this, callerName, callerNumber, audioAsset)
            
            Log.d("FakeCallQuickTile", "Fake call triggered successfully")
            
        } catch (e: Exception) {
            Log.e("FakeCallQuickTile", "Error triggering fake call: ${e.message}")
        }
    }
}

