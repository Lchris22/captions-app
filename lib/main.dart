import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const CaptionsApp());
}

class CaptionsApp extends StatelessWidget {
  const CaptionsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: const HomeScreen(),
    );
  }
}
