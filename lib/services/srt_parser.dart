import 'dart:io';

class Subtitle {
  final int index;
  final Duration start;
  final Duration end;
  final String text;

  Subtitle({
    required this.index,
    required this.start,
    required this.end,
    required this.text,
  });

  int get startMs => start.inMilliseconds;
  int get endMs => end.inMilliseconds;
}

class SrtParser {
  static List<Subtitle> parseSrt(File file) {
    final lines = file.readAsLinesSync();
    final List<Subtitle> subtitles = [];

    int index = 0;
    Duration start = Duration.zero;
    Duration end = Duration.zero;
    String text = "";

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i].trim();

      if (RegExp(r'^\d+$').hasMatch(line)) {
        index = int.parse(line);
      } else if (line.contains("-->")) {
        final times = line.split("-->");
        start = _parseDuration(times[0].trim());
        end = _parseDuration(times[1].trim());
      } else if (line.isEmpty) {
        if (text.isNotEmpty) {
          subtitles.add(Subtitle(index: index, start: start, end: end, text: text.trim()));
          text = "";
        }
      } else {
        text += "$line ";
      }
    }

    if (text.isNotEmpty) {
      subtitles.add(Subtitle(index: index, start: start, end: end, text: text.trim()));
    }

    return subtitles;
  }

  static Duration _parseDuration(String timeString) {
    final parts = timeString.split(RegExp(r'[:,]'));
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    final seconds = int.parse(parts[2]);
    final milliseconds = int.parse(parts[3]);
    return Duration(
      hours: hours,
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );
  }
}
