import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'editor_screen.dart';
import '../services/srt_parser.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  File? videoFile;
  File? srtFile;
  List<Subtitle> subtitles = [];

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    if (result != null) {
      setState(() {
        videoFile = File(result.files.single.path!);
      });
    }
  }

  Future<void> _pickSrt() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['srt']);
    if (result != null) {
      srtFile = File(result.files.single.path!);
      subtitles = SrtParser.parseSrt(srtFile!);
      setState(() {});
    }
  }

  void _proceed() {
    if (videoFile != null && subtitles.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EditorScreen(videoFile: videoFile!, subtitles: subtitles),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select both video and SRT files')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Caption Maker")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.video_library),
              label: Text(videoFile != null ? "Video Selected" : "Pick Video"),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _pickSrt,
              icon: const Icon(Icons.subtitles),
              label: Text(srtFile != null ? "SRT Selected" : "Pick SRT"),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _proceed,
              child: const Text("Start Editing"),
            ),
          ],
        ),
      ),
    );
  }
}
