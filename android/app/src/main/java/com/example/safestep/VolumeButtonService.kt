package com.example.safestep

import android.app.Service
import android.content.Intent
import android.os.IBinder

class VolumeButtonService : Service() {

    override fun onCreate() {
        super.onCreate()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        super.onDestroy()
    }
}
