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
                val intent = android.content.Intent("com.example.safestep.FAKE_CALL_ACCEPTED")
                sendBroadcast(intent)
            }
            override fun onReject() {
                setDisconnected(DisconnectCause(DisconnectCause.REJECTED))
                stopAudio()
                destroy()
                val intent = android.content.Intent("com.example.safestep.FAKE_CALL_REJECTED")
                sendBroadcast(intent)
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
        val path = currentAudioPath ?: return
        var resolvedPath = path
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
            } catch (_: Exception) {}
        }
        try {
            val file = File(resolvedPath)
            if (file.exists()) {
                mediaPlayer = MediaPlayer().apply {
                    setAudioStreamType(android.media.AudioManager.STREAM_VOICE_CALL)
                    setDataSource(file.absolutePath)
                    setOnPreparedListener { start() }
                    setOnCompletionListener { stopAudio() }
                    setOnErrorListener { _, _, _ -> stopAudio(); true }
                    prepareAsync()
                }
            }
        } catch (_: Exception) {}
    }

    private fun stopAudio() {
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
    }
}
