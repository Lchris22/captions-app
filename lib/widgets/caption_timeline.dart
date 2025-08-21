import 'package:flutter/material.dart';
import '../services/srt_parser.dart';

class CaptionTimeline extends StatelessWidget {
  final List<Subtitle> subtitles;
  final Function(int index)? onTap;

  const CaptionTimeline({
    Key? key,
    required this.subtitles,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: subtitles.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final sub = subtitles[index];
        return GestureDetector(
          onTap: () => onTap?.call(index),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              sub.text,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        );
      },
    );
  }
}
