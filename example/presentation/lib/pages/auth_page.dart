import 'package:flutter/material.dart';

class AuthPage extends StatelessWidget {
  const AuthPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Auth')),
      body: const Center(child: Text('Auth')),
    );
  }
}
class AuthViewItem extends StatelessWidget {
  const AuthViewItem({
    required this.id,
    super.key,
  });

  final String id;

  @override
  Widget build(BuildContext context) {
    return ListTile(title: Text(id));
  }
}

