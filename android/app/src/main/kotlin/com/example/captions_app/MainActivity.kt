package com.example.captions_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Register our in-app plugin (since it’s not a pub plugin)
        flutterEngine.plugins.add(NativeEncoderPlugin())
    }
}
