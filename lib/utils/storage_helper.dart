import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<String> getOutputPath() async {
  if (Platform.isAndroid) {
    final dir = await getExternalStorageDirectory();
    final captionsDir = Directory("${dir!.path}/CaptionsApp");

    if (!captionsDir.existsSync()) {
      captionsDir.createSync(recursive: true);
    }

    return "${captionsDir.path}/exported_${DateTime.now().millisecondsSinceEpoch}.mp4";
  }
  throw Exception("Unsupported platform");
}
