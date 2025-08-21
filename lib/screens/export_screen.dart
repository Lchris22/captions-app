import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../painters/caption_painter.dart';
import '../services/srt_parser.dart';
import 'dart:io';
import '../utils/permissions.dart';


class ExportScreen extends StatefulWidget {
  final String videoPath;
  final List<Subtitle> subtitles;
  final int videoWidth;
  final int videoHeight;
  final double videoFps;

  const ExportScreen({
    Key? key,
    required this.videoPath,
    required this.subtitles,
    required this.videoWidth,
    required this.videoHeight,
    required this.videoFps,
  }) : super(key: key);

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  static const _methodChannel = MethodChannel("native_encoder");
  static const _eventChannel = EventChannel("native_encoder/events");

  String _status = "Preparing export...";
  String? _outputPath;

  @override
  void initState() {
    super.initState();
    _startExport();
  }

Future<void> _startExport() async {
  // ✅ Request storage permission before starting export
  if (!await requestStoragePermission()) {
    setState(() {
      _status = "Storage permission denied.";
    });
    return;
  }

  // ✅ Create a dedicated folder inside Downloads
  final Directory downloadsDir =
      Directory("/storage/emulated/0/Download/CaptionsApp");

  if (!downloadsDir.existsSync()) {
    downloadsDir.createSync(recursive: true);
  }

  final outputPath =
      "${downloadsDir.path}/exported_${DateTime.now().millisecondsSinceEpoch}.mp4";

  // ✅ Pre-render all overlays FIRST (important for smoother video)
  for (final subtitle in widget.subtitles) {
    final png = await _renderFrameAt(subtitle.start.inMilliseconds);
    await _methodChannel.invokeMethod("deliverOverlay", {
      "tMs": subtitle.start.inMilliseconds,
      "png": png,
    });
  }

  // ✅ Listen to native plugin requests for overlay frames (backup)
  _eventChannel.receiveBroadcastStream().listen((evt) async {
    final Map<dynamic, dynamic> event = evt as Map<dynamic, dynamic>;

    if (event["type"] == "requestOverlay") {
      final int tMs = event["tMs"];

      // Render overlay on-demand only if missing
      final png = await _renderFrameAt(tMs);

      // Send overlay back to native encoder
      await _methodChannel.invokeMethod("deliverOverlay", {
        "tMs": tMs,
        "png": png,
      });
    }
  });

  // ✅ Start encoding process on native side
  setState(() {
    _status = "Encoding in progress...";
  });

  try {
    await _methodChannel.invokeMethod("start", {
      "inputVideoPath": widget.videoPath,
      "outputPath": outputPath,
      "width": widget.videoWidth,
      "height": widget.videoHeight,
      "fps": widget.videoFps,
      "keepAudio": true,
    });

    setState(() {
      _status = "Export completed!";
      _outputPath = outputPath;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Video saved at: $outputPath")),
    );
  } catch (e) {
    setState(() {
      _status = "Export failed: $e";
    });
  }
}


  Future<Uint8List> _renderFrameAt(int tMs) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final painter = CaptionPainterAtTime(
      subtitles: widget.subtitles,
      timestampMs: tMs,
      style: const TextStyle(
        fontSize: 32,
        color: Colors.white,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            blurRadius: 6,
            color: Colors.black,
            offset: Offset(2, 2),
          ),
        ],
      ),
    );

    painter.paint(
        canvas, Size(widget.videoWidth.toDouble(), widget.videoHeight.toDouble()));

    final picture = recorder.endRecording();
    final img =
        await picture.toImage(widget.videoWidth, widget.videoHeight);
    final byteData =
        await img.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  void _openVideo() {
    if (_outputPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No exported video found.")),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Video saved at: $_outputPath")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Export Video")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_creation, size: 80, color: Colors.blue),
            const SizedBox(height: 20),
            Text(_status, style: const TextStyle(fontSize: 18)),
            if (_outputPath != null) ...[
              const SizedBox(height: 20),
              const Text("Saved to:", style: TextStyle(fontWeight: FontWeight.bold)),
              Text(_outputPath!, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 15),
              ElevatedButton(
                onPressed: _openVideo,
                child: const Text("Play Exported Video"),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
