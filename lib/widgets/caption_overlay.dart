import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/subtitle_model.dart';

class CaptionOverlay extends StatelessWidget {
  final VideoPlayerController controller;
  final List<SubtitleLine> subtitles;

  const CaptionOverlay({
    required this.controller,
    required this.subtitles,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final pos = controller.value.position.inMilliseconds;
        final currentLine = subtitles.firstWhere(
          (s) => pos >= s.start && pos <= s.end,
          orElse: () => SubtitleLine(start: 0, end: 0, text: "", words: []),
        );
        return CustomPaint(
          painter: CaptionPainter(currentLine, pos),
        );
      },
    );
  }
}

class CaptionPainter extends CustomPainter {
  final SubtitleLine line;
  final int currentTime;

  CaptionPainter(this.line, this.currentTime);

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );

    final visibleWords = <TextSpan>[];
    for (var w in line.words) {
      if (currentTime >= w.start) {
        final opacity = (currentTime < w.start + 200)
            ? (currentTime - w.start) / 200.0
            : 1.0;
        visibleWords.add(TextSpan(
          text: "${w.word} ",
          style: TextStyle(
            fontSize: 24,
            color: Colors.white.withOpacity(opacity),
            shadows: [
              Shadow(blurRadius: 4, color: Colors.black, offset: Offset(1, 1))
            ],
          ),
        ));
      }
    }

    tp.text = TextSpan(children: visibleWords);
    tp.layout(maxWidth: size.width * 0.9);

    final offset = Offset(
      (size.width - tp.width) / 2,
      size.height * 0.75,
    );

    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
