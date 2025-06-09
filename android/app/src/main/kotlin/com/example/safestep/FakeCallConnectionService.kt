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
        // Only use "audioPath"; asset-to-cache is always handled by Flutter
        currentAudioPath = extras?.getString("audioPath")
        val connection = object : Connection() {
            override fun onAnswer() {
                setActive()
                playSelectedAudio()
            }
            override fun onDisconnect() {
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
        android.util.Log.i("FakeCall", "Attempting to play audio from path: $path")
        try {
            val file = File(path)
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
                android.util.Log.e("FakeCall", "Audio file not found: $path")
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
