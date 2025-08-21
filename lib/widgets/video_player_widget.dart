import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../widgets/caption_overlay.dart';
import '../models/subtitle_model.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoPath;
  final List<SubtitleLine> subtitles;

  const VideoPlayerWidget({
    required this.videoPath,
    required this.subtitles,
    Key? key,
  }) : super(key: key);

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  late VideoPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(Uri.parse(widget.videoPath))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Center(
          child: _controller.value.isInitialized
              ? AspectRatio(
                  aspectRatio: _controller.value.aspectRatio,
                  child: VideoPlayer(_controller),
                )
              : const CircularProgressIndicator(),
        ),
        if (_controller.value.isInitialized)
          Positioned.fill(
            child: CaptionOverlay(
              controller: _controller,
              subtitles: widget.subtitles,
            ),
          ),
      ],
    );
  }
}
