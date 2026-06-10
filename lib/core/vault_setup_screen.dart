import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'vault_service.dart';
import '../screens/home_screen.dart';
import '../shared/widgets/progress.dart';

class VaultSetupScreen extends StatefulWidget {
  const VaultSetupScreen({super.key});

  @override
  State<VaultSetupScreen> createState() => _VaultSetupScreenState();
}

class _VaultSetupScreenState extends State<VaultSetupScreen> {
  String? _selectedPath;
  bool _isLoading = false;

  Future<void> _pickFolder() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null && mounted) {
      setState(() => _selectedPath = path);
    }
  }

  Future<void> _confirm() async {
    if (_selectedPath == null) return;
    setState(() => _isLoading = true);
    try {
      await VaultService.ensureVaultDirectories(_selectedPath!);
      await VaultService.setVaultPath(_selectedPath!);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose Vault'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        top: false,
        child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select the folder where your Markdown notes will be stored. '
              'This is typically your Obsidian vault folder.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _pickFolder,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose folder'),
            ),
            if (_selectedPath != null) ...[
              const SizedBox(height: 12),
              Text(
                _selectedPath!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 6),
              Text(
                'Will create: Interesting/Projects  ·  Interesting/Templates  ·  Interesting/System',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_selectedPath == null || _isLoading) ? null : _confirm,
                child: _isLoading
                    ? const InlineSpinner(size: 20, color: Colors.white)
                    : const Text('Get Started'),
              ),
            ),
          ],
        ),
      )),
    );
  }
}
