// screens/saved_workers_screen.dart
import 'package:flutter/material.dart';

class SavedWorkersScreen extends StatelessWidget {
  const SavedWorkersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Workers'),
      ),
      body: const Center(
        child: Text('Saved Workers Screen'),
      ),
    );
  }
}
