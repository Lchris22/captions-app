// lib/services/native_encoder.dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

class NativeEncoder {
  static const _ch = MethodChannel('native_encoder');
  static const _events = EventChannel('native_encoder/events');

  // Init with export params
  static Future<void> start({
    required String inputVideoPath,
    required String outputPath,
    required int width,
    required int height,
    required double fps,
    required bool keepAudio,
  }) {
    return _ch.invokeMethod('start', {
      'inputVideoPath': inputVideoPath,
      'outputPath': outputPath,
      'width': width,
      'height': height,
      'fps': fps,
      'keepAudio': keepAudio,
    });
  }

  // Called by native: “I need overlay for this ms”
  // You’ll wire this in Preview/Export screen.
  static Stream<Map> onFrameRequest() =>
      _events.receiveBroadcastStream().cast<Map>();

  // Send overlay RGBA/PNG back for a timestamp
  static Future<void> deliverOverlay({
    required int tMs,
    required Uint8List pngBytes,
  }) {
    return _ch.invokeMethod('deliverOverlay', {
      'tMs': tMs,
      'png': pngBytes,
    });
  }

  // Finish and get output path
  static Future<String> finish() async {
    final p = await _ch.invokeMethod<String>('finish');
    return p!;
  }

  static Future<void> cancel() => _ch.invokeMethod('cancel');
}
