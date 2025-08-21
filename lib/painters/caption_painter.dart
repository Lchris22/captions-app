import 'package:flutter/material.dart';
import '../services/srt_parser.dart';

class CaptionPainterAtTime extends CustomPainter {
  final List<Subtitle> subtitles;
  final int timestampMs;
  final TextStyle style;

  CaptionPainterAtTime({
    required this.subtitles,
    required this.timestampMs,
    required this.style,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final matched = subtitles.where((s) =>
        timestampMs >= s.start.inMilliseconds &&
        timestampMs <= s.end.inMilliseconds).toList();

    if (matched.isEmpty) return;

    final textSpan = TextSpan(text: matched.first.text, style: style);
    final tp = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    tp.layout(maxWidth: size.width);
    tp.paint(
      canvas,
      Offset((size.width - tp.width) / 2, size.height - tp.height - 20),
    );
  }

  @override
  bool shouldRepaint(covariant CaptionPainterAtTime oldDelegate) {
    return oldDelegate.timestampMs != timestampMs;
  }
}
