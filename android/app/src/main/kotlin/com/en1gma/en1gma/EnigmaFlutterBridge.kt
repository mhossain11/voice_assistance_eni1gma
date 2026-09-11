package com.en1gma.en1gma

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/** Process-local bridge: service remains safe if Flutter has no active engine. */
object EnigmaFlutterBridge {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var pendingWakeEvent = false
    @Volatile private var serviceState = "stopped"

    fun connect(eventSink: EventChannel.EventSink?) {
        mainHandler.post {
            sink = eventSink
            sink?.success(mapOf("event" to "service_state_changed", "state" to serviceState))
            if (pendingWakeEvent && sink != null) {
                pendingWakeEvent = false
                sink?.success(mapOf("event" to "wake_word_detected"))
            }
        }
    }

    fun disconnect() = mainHandler.post { sink = null }

    fun wakeWordDetected() {
        mainHandler.post {
            val activeSink = sink
            if (activeSink != null) activeSink.success(mapOf("event" to "wake_word_detected")) else pendingWakeEvent = true
        }
    }

    fun serviceStateChanged(state: String) {
        serviceState = state
        mainHandler.post {
            sink?.success(mapOf("event" to "service_state_changed", "state" to state))
        }
    }

    fun serviceError(message: String) {
        mainHandler.post {
            sink?.success(mapOf("event" to "service_error", "message" to message))
        }
    }

    fun currentServiceState(): String = serviceState
}
