// lib/services/overlay_renderer.dart
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/widgets.dart';

typedef PaintFn = void Function(Canvas, Size);

Future<Uint8List> renderOverlayPng({
  required int width,
  required int height,
  required void Function(Canvas canvas, Size size) paintCaptions,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(width.toDouble(), height.toDouble());

  // Transparent background (do nothing = transparent)
  // Draw captions
  paintCaptions(canvas, size);

  final picture = recorder.endRecording();
  final img = await picture.toImage(width, height);
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
