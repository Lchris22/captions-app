import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';
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

  StreamSubscription? _eventSub;
  bool _started = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startExport());
  }
  @override
  void dispose() {
    _disposed = true;
    _eventSub?.cancel();
    super.dispose();
  }

 Future<void> _startExport() async {
    if (_started) return;
    _started = true;

    // Permissions once
    final ok = await requestStoragePermission();
    if (!ok) {
      setState(() => _status = "Storage permission denied.");
      return;
    }

    // Output file path
    final downloadsDir = Directory("/storage/emulated/0/Download/CaptionsApp");
    if (!downloadsDir.existsSync()) {
      downloadsDir.createSync(recursive: true);
    }
    final outputPath =
        "${downloadsDir.path}/exported_${DateTime.now().millisecondsSinceEpoch}.mp4";

    // Event stream: single subscription
    _eventSub = _eventChannel.receiveBroadcastStream().listen((evt) async {
      if (_disposed) return;
      final Map<dynamic, dynamic> event = evt as Map<dynamic, dynamic>;
      if (event["type"] == "requestOverlay") {
        final int tMs = event["tMs"];
        try {
          final png = await _renderFrameAt(tMs);
          if (_disposed) return;
          await _methodChannel.invokeMethod("deliverOverlay", {
            "tMs": tMs,
            "png": png,
          });
        } catch (e) {
          // Best-effort: skip this frame
        }
      }
    });

    setState(() => _status = "Encoding in progress...");

    // Optional: small prewarm to reduce early stalls (first 500ms in 33ms steps)
    try {
      final preStart = widget.subtitles.isNotEmpty ? widget.subtitles.first.start.inMilliseconds : 0;
      for (int t = preStart; t < preStart + 500; t += 33) {
        final png = await _renderFrameAt(t);
        await _methodChannel.invokeMethod("deliverOverlay", {"tMs": t, "png": png});
      }
    } catch (_) {}

    // Start native
    try {
      await _methodChannel.invokeMethod("start", {
        "inputVideoPath": widget.videoPath,
        "outputPath": outputPath,
        "width": widget.videoWidth,
        "height": widget.videoHeight,
        "fps": widget.videoFps,
        "keepAudio": false, // keep false for stability; add audio later
      });

      // When native finishes it will close muxer; we can call finish to clean state
      final path = await _methodChannel.invokeMethod<String>("finish");
      if (!_disposed) {
        setState(() {
          _status = "Export completed!";
          _outputPath = path ?? outputPath;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Video saved at: $_outputPath")),
          );
        }
      }
    } catch (e) {
      if (!_disposed) {
        setState(() => _status = "Export failed: $e");
      }
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
