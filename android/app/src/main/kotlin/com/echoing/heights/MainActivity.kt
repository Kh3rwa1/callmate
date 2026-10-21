package com.echoing.heights

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// FlutterFragmentActivity (a ComponentActivity) so enableEdgeToEdge() is available.
class MainActivity : FlutterFragmentActivity() {
    private var playback: SarvamAudioPlayback? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Draw behind the status and navigation bars on every Android version, as Android 15+
        // does for apps targeting SDK 35+. Flutter gets the bar sizes as MediaQuery padding, and
        // the Dart side only sets bar icon colours (lib/core/theme/system_bars.dart).
        enableEdgeToEdge()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        playback = SarvamAudioPlayback(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        playback?.detach()
        playback = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
