import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

Future<bool> requestStoragePermission() async {
  if (!Platform.isAndroid) return true;

  final androidVersion = int.parse((await Process.run('getprop', ['ro.build.version.sdk']))
      .stdout
      .toString()
      .trim());

  // ✅ For Android 15 & above → Use app-specific storage (no special permissions needed)
  if (androidVersion >= 35) {
    return true;
  }

  // ✅ Android 11 to 14 → MANAGE_EXTERNAL_STORAGE
  if (androidVersion >= 30) {
    final status = await Permission.manageExternalStorage.request();
    return status.isGranted;
  }

  // ✅ Android 10 and below → Legacy storage permission
  final status = await Permission.storage.request();
  return status.isGranted;
}
