import 'package:flutter/material.dart';

void main() {
  runApp(const CleanArchitectApp());
}

class CleanArchitectApp extends StatelessWidget {
  const CleanArchitectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clean Architect',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(child: Text('Clean Architect')),
      ),
    );
  }
}
