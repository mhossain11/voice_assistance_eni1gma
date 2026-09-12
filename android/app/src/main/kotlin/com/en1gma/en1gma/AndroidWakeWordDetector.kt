package com.en1gma.en1gma

import android.content.Context
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.util.Log
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.nio.FloatBuffer
import java.util.Collections
import kotlin.math.max

/** Foreground-only 16 kHz PCM16 -> official mel ONNX -> supplied EN1GMA classifier. */
class AndroidWakeWordDetector(
    private val context: Context,
    private val onDetected: () -> Unit,
    private val onCaptureFailure: (Int) -> Unit,
) : AutoCloseable {
    private val environment = OrtEnvironment.getEnvironment()
    private val melSession = sessionFromAsset("melspectrogram.onnx")
    private val classifierSession = sessionFromAsset("enigma.onnx")
    private val windowSamples = 98 * 160 + 400 // 10 ms hop, 25 ms window at 16 kHz.
    private var consecutive = 0
    private var lastDetectionAt = 0L
    private var recording: AudioRecord? = null
    private var worker: Thread? = null
    @Volatile private var running = false

    fun isWorkerAlive(): Boolean = worker?.isAlive == true
    fun isRecording(): Boolean = recording?.recordingState == AudioRecord.RECORDSTATE_RECORDING

    @Synchronized fun start() {
        if (running) return
        val minBuffer = AudioRecord.getMinBufferSize(16_000, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        require(minBuffer > 0) { "The device does not support 16 kHz mono PCM microphone capture." }
        val newRecording = AudioRecord(MediaRecorder.AudioSource.VOICE_RECOGNITION, 16_000, AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT, max(minBuffer, 4096))
        try {
            require(newRecording.state == AudioRecord.STATE_INITIALIZED) { "Microphone initialization failed." }
            Log.i(tag, "[ENIGMA-AUDIO] AudioRecord state=${newRecording.state}")
            newRecording.startRecording()
            require(newRecording.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                "Microphone did not enter the recording state."
            }
            recording = newRecording
        } catch (error: Exception) {
            newRecording.release()
            throw error
        }
        Log.i(tag, "[ENIGMA-AUDIO] recordingState=${newRecording.recordingState}")
        running = true
        worker = Thread(::captureLoop, "En1gmaWakeWord").also { it.start() }
        Log.i(tag, "[WAKE] Listener started")
    }

    @Synchronized fun stop() {
        running = false
        val activeWorker = worker
        activeWorker?.interrupt()
        if (activeWorker != null && activeWorker !== Thread.currentThread()) activeWorker.join(750)
        worker = null
        recording?.runCatching { stop() }; recording?.release(); recording = null; consecutive = 0
    }

    private fun captureLoop() {
        val ring = ShortArray(windowSamples); var count = 0; var write = 0; val readBuffer = ShortArray(640)
        var readErrors = 0
        while (running) {
            val read = recording?.read(readBuffer, 0, readBuffer.size, AudioRecord.READ_BLOCKING) ?: break
            if (read < 0) {
                Log.w(tag, "[ENIGMA-AUDIO] readError=$read")
                if (++readErrors >= maxReadErrors && running) {
                    running = false
                    onCaptureFailure(read)
                    break
                }
                continue
            }
            if (read == 0) continue
            readErrors = 0
            for (index in 0 until read) { ring[write] = readBuffer[index]; write = (write + 1) % ring.size; if (count < ring.size) count++ }
            if (count == ring.size) evaluate(ShortArray(ring.size) { ring[(write + it) % ring.size] })
        }
    }

    private fun evaluate(pcm: ShortArray) = try {
        val audio = FloatArray(pcm.size) { pcm[it].toFloat() }
        val melInput = OnnxTensor.createTensor(environment, FloatBuffer.wrap(audio), longArrayOf(1, audio.size.toLong()))
        val melResult = melSession.run(Collections.singletonMap(melSession.inputNames.first(), melInput))
        @Suppress("UNCHECKED_CAST") val mel = melResult[0].value as Array<Array<Array<FloatArray>>>
        melInput.close(); melResult.close()
        val frames = mel[0][0]; val flat = FloatArray(98 * 32); val start = max(0, frames.size - 98)
        for (frame in 0 until 98) for (bin in 0 until 32) if (start + frame < frames.size) flat[frame * 32 + bin] = frames[start + frame][bin] / 10f + 2f
        val input = OnnxTensor.createTensor(environment, FloatBuffer.wrap(flat), longArrayOf(1, 98, 32))
        val result = classifierSession.run(Collections.singletonMap(classifierSession.inputNames.first(), input))
        @Suppress("UNCHECKED_CAST") val scores = result[0].value as Array<FloatArray>
        val score = scores[0][0]; input.close(); result.close()
        consecutive = if (score >= 0.5f) consecutive + 1 else 0
        if (consecutive >= 3 && System.currentTimeMillis() - lastDetectionAt > 2_000) {
            consecutive = 0; lastDetectionAt = System.currentTimeMillis(); Log.i(tag, "[WAKE] Enigma detected ($score)"); onDetected()
        }
        Unit
    } catch (exception: Exception) { Log.e(tag, "Wake-word inference error", exception) }

    private fun sessionFromAsset(name: String): OrtSession = context.assets.open(name).use { environment.createSession(it.readBytes(), OrtSession.SessionOptions()) }
    override fun close() { stop(); melSession.close(); classifierSession.close() }
    private companion object {
        const val tag = "EN1GMA"
        const val maxReadErrors = 3
    }
}
