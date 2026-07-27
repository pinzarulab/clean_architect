import 'package:di/di.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDi(get: GetIt.instance);
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
      home: const Scaffold(body: Center(child: Text('Clean Architect'))),
    );
  }
}
