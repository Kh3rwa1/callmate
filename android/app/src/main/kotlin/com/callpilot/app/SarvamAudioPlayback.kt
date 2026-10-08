package com.callpilot.app

import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * Native PCM playback for sarvamconv_ai_sdk. Its DefaultAudioInterface sends
 * the agent's 16-bit mono audio to this channel on Android; without a handler
 * the voice agent is silent (MissingPluginException on `init`).
 */
class SarvamAudioPlayback(messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.sarvam.audio/playback")
    private val queue = LinkedBlockingQueue<ByteArray>()

    @Volatile private var player: Player? = null
    private var sampleRate = 16000

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "init" -> {
                    init(call.argument<Int>("sampleRate") ?: 16000)
                    result.success(true)
                }
                "play" -> {
                    val data = call.argument<ByteArray>("audioData")
                    if (data == null) {
                        result.error("INVALID_DATA", "Audio data is null", null)
                    } else {
                        if (player == null) init(sampleRate)
                        queue.add(data)
                        result.success(true)
                    }
                }
                "stop" -> {
                    stop()
                    result.success(true)
                }
                "dispose" -> {
                    dispose()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun init(rate: Int) {
        if (player != null && rate == sampleRate) return
        dispose()
        sampleRate = rate
        player = Player(rate, queue).also { it.start() }
    }

    /** Barge-in: drop queued and already-buffered audio, keep the track ready. */
    private fun stop() {
        queue.clear()
        player?.flush()
    }

    fun dispose() {
        player?.shutdown()
        player = null
        queue.clear()
    }

    fun detach() {
        dispose()
        channel.setMethodCallHandler(null)
    }
}

/** One AudioTrack and the thread that feeds it; never reused after [shutdown]. */
private class Player(rate: Int, private val queue: LinkedBlockingQueue<ByteArray>) : Thread("sarvam-playback") {
    @Volatile private var running = true
    private val track: AudioTrack = AudioTrack.Builder()
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build(),
        )
        .setAudioFormat(
            AudioFormat.Builder()
                .setSampleRate(rate)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                .build(),
        )
        .setBufferSizeInBytes(
            AudioTrack.getMinBufferSize(
                rate, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_16BIT,
            ) * 4,
        )
        .setTransferMode(AudioTrack.MODE_STREAM)
        .build()

    override fun run() {
        try {
            track.play()
            var played = 0L
            while (running) {
                val chunk = queue.poll(20, TimeUnit.MILLISECONDS) ?: continue
                if (!running) break
                if (played == 0L) Log.i("SarvamAudio", "first agent audio chunk (${chunk.size} bytes)")
                played += track.write(chunk, 0, chunk.size, AudioTrack.WRITE_BLOCKING).coerceAtLeast(0)
            }
            if (played > 0) Log.i("SarvamAudio", "played $played bytes")
        } catch (_: InterruptedException) {
        } catch (_: IllegalStateException) {
        } finally {
            track.release()
        }
    }

    fun flush() {
        try {
            track.pause()
            track.flush()
            track.play()
        } catch (_: IllegalStateException) {
        }
    }

    fun shutdown() {
        running = false
        interrupt()
    }
}
