package com.example.roadrescue

import android.Manifest
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var microphoneRecorder: AudioRecord? = null
    private var microphoneThread: Thread? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "roadrescue/microphone_rms",
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                startMicrophone(arguments, events)
            }

            override fun onCancel(arguments: Any?) {
                stopMicrophone()
            }
        })
    }

    override fun onDestroy() {
        stopMicrophone()
        super.onDestroy()
    }

    private fun startMicrophone(
        arguments: Any?,
        events: EventChannel.EventSink,
    ) {
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            events.error("permission_denied", "Microphone permission is required.", null)
            return
        }

        val sampleRate = (arguments as? Map<*, *>)?.get("sampleRate") as? Int ?: 16000
        val minBufferSize = AudioRecord.getMinBufferSize(
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
        )
        if (minBufferSize <= 0) {
            events.error("audio_unavailable", "Microphone input is unavailable.", null)
            return
        }

        val recorder = AudioRecord(
            MediaRecorder.AudioSource.MIC,
            sampleRate,
            AudioFormat.CHANNEL_IN_MONO,
            AudioFormat.ENCODING_PCM_16BIT,
            maxOf(minBufferSize, 2048),
        )
        if (recorder.state != AudioRecord.STATE_INITIALIZED) {
            recorder.release()
            events.error("audio_unavailable", "Microphone could not be initialized.", null)
            return
        }

        stopMicrophone()
        microphoneRecorder = recorder
        try {
            recorder.startRecording()
        } catch (error: Exception) {
            microphoneRecorder = null
            recorder.release()
            events.error("audio_start_failed", error.message, null)
            return
        }

        microphoneThread = Thread({
            val samples = ShortArray(1024)
            while (!Thread.currentThread().isInterrupted && microphoneRecorder === recorder) {
                val count = recorder.read(samples, 0, samples.size)
                if (count <= 0) {
                    if (count < 0) {
                        mainHandler.post {
                            if (microphoneRecorder === recorder) {
                                events.error("audio_read_failed", "Microphone input stopped.", null)
                                stopMicrophone()
                            }
                        }
                    }
                    break
                }
                var squareSum = 0.0
                for (index in 0 until count) {
                    val sample = samples[index].toDouble()
                    squareSum += sample * sample
                }
                val rms = sqrt(squareSum / count) / Short.MAX_VALUE
                mainHandler.post {
                    if (microphoneRecorder === recorder) events.success(rms)
                }
            }
        }, "RoadRescueMicRms").apply {
            isDaemon = true
            start()
        }
    }

    private fun stopMicrophone() {
        val thread = microphoneThread
        microphoneThread = null
        thread?.interrupt()

        val recorder = microphoneRecorder
        microphoneRecorder = null
        if (recorder != null) {
            try {
                if (recorder.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                    recorder.stop()
                }
            } catch (_: IllegalStateException) {
                // The stream may already have stopped.
            } finally {
                recorder.release()
            }
        }
    }
}
