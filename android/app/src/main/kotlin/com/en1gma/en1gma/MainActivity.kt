package com.en1gma.en1gma

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Flutter sends commands; the foreground service owns microphone capture. */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.en1gma/wake_word").setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize", "getWakeWordServiceState" -> result.success(EnigmaFlutterBridge.currentServiceState())
                "start", "resume", "startWakeWord", "resumeWakeWord" -> if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                    ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.RECORD_AUDIO), 1001)
                    result.error("MICROPHONE_PERMISSION_REQUIRED", "Allow microphone access, then tap Start listening again.", null)
                } else try {
                    ContextCompat.startForegroundService(this, EnigmaWakeWordService.commandIntent(this, EnigmaWakeWordService.ACTION_RESUME))
                    result.success(null)
                } catch (exception: Exception) { result.error("START_FAILED", exception.message, null) }
                "pause", "pauseWakeWord" -> { startService(EnigmaWakeWordService.commandIntent(this, EnigmaWakeWordService.ACTION_PAUSE)); result.success(null) }
                "stop", "shutdown", "stopWakeWord" -> { stopService(EnigmaWakeWordService.commandIntent(this, EnigmaWakeWordService.ACTION_STOP)); result.success(null) }
                else -> result.notImplemented()
            }
        }
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.en1gma/wake_word_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { EnigmaFlutterBridge.connect(sink) }
            override fun onCancel(arguments: Any?) { EnigmaFlutterBridge.disconnect() }
        })
    }
}
