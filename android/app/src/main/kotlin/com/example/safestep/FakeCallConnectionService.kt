package com.example.safestep

import android.content.Context
import android.media.MediaPlayer
import android.net.Uri
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.PhoneAccountHandle
import android.telecom.DisconnectCause
import android.telecom.TelecomManager
import java.io.File
import java.io.FileOutputStream

class FakeCallConnectionService : ConnectionService() {
    private var mediaPlayer: MediaPlayer? = null
    private var currentAudioPath: String? = null
    private var currentCallerName: String = "Unknown"
    private var currentCallerNumber: String = ""

    override fun onCreateIncomingConnection(
        connectionManagerPhoneAccount: PhoneAccountHandle?,
        request: ConnectionRequest?
    ): Connection {
        val extras = request?.extras
        currentCallerName = extras?.getString("callerName") ?: "Unknown"
        currentCallerNumber = extras?.getString("callerNumber") ?: ""
        currentAudioPath = extras?.getString("audioPath")
        val connection = object : Connection() {
            override fun onAnswer() {
                setActive()
                playSelectedAudio()
                // Notify shake service: call accepted
                val intent = android.content.Intent("com.example.safestep.FAKE_CALL_ACCEPTED")
                sendBroadcast(intent)
            }
            override fun onReject() {
                // Called when the user rejects the call from the incoming call UI
                setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
                stopAudio()
                destroy()
                val intent = android.content.Intent("com.example.safestep.FAKE_CALL_REJECTED")
                sendBroadcast(intent)
            }
            override fun onDisconnect() {
                // Called when the call is ended (either after answer or after reject)
                setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
                stopAudio()
                destroy()
            }
        }
        connection.setAddress(Uri.fromParts("tel", currentCallerNumber, null), TelecomManager.PRESENTATION_ALLOWED)
        connection.setCallerDisplayName(currentCallerName, TelecomManager.PRESENTATION_ALLOWED)
        connection.setRinging()
        return connection
    }

    private fun playSelectedAudio() {
        stopAudio()
        val path = currentAudioPath ?: run {
            android.util.Log.e("FakeCall", "No audio path provided!")
            return
        }
        var resolvedPath = path
        // If the path is an asset, copy it to cache so native can read it
        if (!File(path).exists() && path.startsWith("assets/")) {
            try {
                val cacheFile = File(cacheDir, File(path).name)
                if (!cacheFile.exists()) {
                    val assetManager = applicationContext.assets
                    assetManager.open(path.removePrefix("assets/")).use { input ->
                        FileOutputStream(cacheFile).use { output ->
                            input.copyTo(output)
                        }
                    }
                }
                resolvedPath = cacheFile.absolutePath
            } catch (e: Exception) {
                android.util.Log.e("FakeCall", "Failed to copy asset to cache: ${e.message}", e)
            }
        }
        android.util.Log.i("FakeCall", "Attempting to play audio from path: $resolvedPath")
        try {
            val file = File(resolvedPath)
            android.util.Log.i("FakeCall", "File exists: ${file.exists()} | Size: ${if (file.exists()) file.length() else 0}")
            if (file.exists()) {
                mediaPlayer = MediaPlayer().apply {
                    setAudioStreamType(android.media.AudioManager.STREAM_VOICE_CALL)
                    setDataSource(file.absolutePath)
                    setOnPreparedListener {
                        android.util.Log.i("FakeCall", "MediaPlayer prepared, starting playback.")
                        start() 
                    }
                    setOnCompletionListener { 
                        android.util.Log.i("FakeCall", "MediaPlayer completed playback.")
                        stopAudio() 
                    }
                    setOnErrorListener { mp, what, extra ->
                        android.util.Log.e("FakeCall", "MediaPlayer error: what=$what, extra=$extra")
                        stopAudio()
                        true
                    }
                    prepareAsync()
                }
            } else {
                android.util.Log.e("FakeCall", "Audio file not found: $resolvedPath")
            }
        } catch (e: Exception) {
            android.util.Log.e("FakeCall", "Exception during audio playback: ${e.message}", e)
        }
    }

    private fun stopAudio() {
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
    }
}
