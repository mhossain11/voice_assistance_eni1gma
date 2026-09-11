package com.en1gma.en1gma

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

class EnigmaWakeWordService : Service() {
    private var detector: AndroidWakeWordDetector? = null
    private var nativeState = NativeState.STOPPED

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopService()
            ACTION_PAUSE -> pauseDetection()
            ACTION_START, ACTION_RESUME, null -> startDetection()
        }
        return if (nativeState == NativeState.STOPPED) START_NOT_STICKY else START_STICKY
    }

    @Synchronized
    private fun startDetection() {
        if (nativeState == NativeState.LISTENING_FOR_WAKE_WORD || nativeState == NativeState.STARTING) return
        setState(NativeState.STARTING)
        try {
            startForegroundWithNotification()
            if (detector == null) detector = AndroidWakeWordDetector(applicationContext) {
                Log.i(tag, "[ENIGMA-WAKE] wake word detected")
                pauseDetection()
                Log.i(tag, "[ENIGMA-BRIDGE] wake_word_detected")
                EnigmaFlutterBridge.wakeWordDetected()
            }
            detector!!.start()
            setState(NativeState.LISTENING_FOR_WAKE_WORD)
            Log.i(tag, "[ENIGMA-WAKE] listening")
        } catch (error: Exception) {
            setState(NativeState.PAUSED)
            Log.e(tag, "[ENIGMA-SERVICE] wake-word start failed", error)
            EnigmaFlutterBridge.serviceError("Wake-word detection could not start.")
            updateNotification("Wake-word detection paused")
        }
    }

    @Synchronized
    private fun pauseDetection() {
        if (nativeState == NativeState.PAUSED) return
        if (nativeState == NativeState.STOPPED) {
            stopSelf()
            return
        }
        detector?.stop() // Releases AudioRecord before Flutter SpeechRecognizer can own the mic.
        setState(NativeState.PAUSED)
        updateNotification("Wake-word detection paused")
        Log.i(tag, "[ENIGMA-AUDIO] microphone released")
    }

    @Synchronized
    private fun stopService() {
        if (nativeState == NativeState.STOPPED || nativeState == NativeState.STOPPING) return
        setState(NativeState.STOPPING)
        detector?.close()
        detector = null
        setState(NativeState.STOPPED)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
        Log.i(tag, "[ENIGMA-SERVICE] stopped")
    }

    private fun startForegroundWithNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(channelId, "EN1GMA wake word", NotificationManager.IMPORTANCE_LOW))
        }
        val notification: Notification = notification("Listening for \"Enigma\"")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(notificationId, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
        } else startForeground(notificationId, notification)
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java).notify(notificationId, notification(text))
    }

    private fun notification(text: String): Notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("EN1GMA")
            .setContentText(text)
            .setOngoing(true)
            .build()

    private fun setState(next: NativeState) {
        if (nativeState == next) return
        nativeState = next
        EnigmaFlutterBridge.serviceStateChanged(next.wireName)
        Log.i(tag, "[ENIGMA-STATE] ${next.wireName}")
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        detector?.close()
        detector = null
        setState(NativeState.STOPPED)
        Log.i(tag, "[ENIGMA-SERVICE] destroyed")
        super.onDestroy()
    }

    private enum class NativeState(val wireName: String) {
        STOPPED("stopped"), STARTING("starting"), LISTENING_FOR_WAKE_WORD("listening"), PAUSED("paused"), STOPPING("stopping")
    }
    companion object {
        const val tag = "EN1GMA"
        const val channelId = "en1gma_wake_word"
        const val notificationId = 7001
        const val ACTION_START = "com.en1gma.action.START_WAKE_WORD"
        const val ACTION_PAUSE = "com.en1gma.action.PAUSE_WAKE_WORD"
        const val ACTION_RESUME = "com.en1gma.action.RESUME_WAKE_WORD"
        const val ACTION_STOP = "com.en1gma.action.STOP_WAKE_WORD"
        fun commandIntent(context: android.content.Context, action: String) = Intent(context, EnigmaWakeWordService::class.java).setAction(action)
    }
}
