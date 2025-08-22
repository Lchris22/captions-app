import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

Future<bool> requestStoragePermission() async {
  if (!Platform.isAndroid) return true;

  // Android 11+ (API 30+) — manageExternalStorage
  final sdkInt = (await Permission.storage.status).isGranted ? null : null; // harmless
  final release = Platform.version; // not reliable, so just try both

  // Try manageExternalStorage first (it’s a superset, only exists on API30+)
  if (await Permission.manageExternalStorage.isDenied) {
    final status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) {
      // Fallback to normal storage on some OEMs/SDK combos
      final s = await Permission.storage.request();
      return s.isGranted;
    }
    return true;
  }

  // Otherwise normal storage
  if (await Permission.storage.isDenied) {
    final s = await Permission.storage.request();
    return s.isGranted;
  }
  return true;
}
