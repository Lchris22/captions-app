import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../painters/caption_painter.dart';
import '../services/srt_parser.dart';
import 'export_screen.dart';
import '../widgets/caption_timeline.dart';

class EditorScreen extends StatefulWidget {
  final File videoFile;
  final List<Subtitle> subtitles;

  const EditorScreen({
    Key? key,
    required this.videoFile,
    required this.subtitles,
  }) : super(key: key);

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late VideoPlayerController _controller;
  int currentPosition = 0;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) => setState(() {}))
      ..addListener(() {
        setState(() {
          currentPosition = _controller.value.position.inMilliseconds;
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startExport() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExportScreen(
          videoPath: widget.videoFile.path,
          subtitles: widget.subtitles,
          videoWidth: _controller.value.size.width.toInt(),
          videoHeight: _controller.value.size.height.toInt(),
          videoFps: _controller.value.playbackSpeed, // keep this for FPS
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Caption Editor")),
      body: Column(
        children: [
          if (_controller.value.isInitialized)
            AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                children: [
                  VideoPlayer(_controller),
                  CustomPaint(
                    painter: CaptionPainterAtTime(
                      subtitles: widget.subtitles,
                      timestampMs: currentPosition,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            blurRadius: 6,
                            color: Colors.black,
                            offset: Offset(2, 2),
                          ),
                        ],
                      ),
                    ),
                    child: Container(),
                  ),
                ],
              ),
            ),
          ElevatedButton(
            onPressed: _startExport,
            child: const Text("Export"),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 1,
                  child: CaptionTimeline(
                    subtitles: widget.subtitles,
                    onTap: (index) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Edit caption ${index + 1} coming soon!')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
