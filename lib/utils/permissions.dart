import 'package:permission_handler/permission_handler.dart';
import 'dart:io';

Future<bool> requestStoragePermission() async {
  if (Platform.isAndroid) {
    // ✅ Android 11+ (API 30+)
    if (await Permission.manageExternalStorage.isGranted) {
      return true;
    }

    final manageStatus = await Permission.manageExternalStorage.request();
    if (manageStatus.isGranted) return true;

    // If permanently denied, open app settings
    if (manageStatus.isPermanentlyDenied) {
      await openAppSettings();
      return false;
    }

    // ✅ Android 10 and below → Request normal storage permission
    if (await Permission.storage.isGranted) {
      return true;
    }

    final storageStatus = await Permission.storage.request();
    if (storageStatus.isGranted) return true;

    if (storageStatus.isPermanentlyDenied) {
      await openAppSettings();
    }

    return false;
  }

  // iOS → No storage permissions required
  return true;
}
