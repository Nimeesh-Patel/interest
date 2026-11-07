import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../features/sync/home_screen.dart';
import '../shared/constants/app_text_styles.dart';
import '../shared/constants/app_theme.dart';
import 'vault_service.dart';

/// First run: choose the Obsidian vault. Interest creates nothing in it.
class VaultSetupScreen extends StatefulWidget {
  const VaultSetupScreen({super.key});

  @override
  State<VaultSetupScreen> createState() => _VaultSetupScreenState();
}

class _VaultSetupScreenState extends State<VaultSetupScreen> {
  String? _path;

  Future<void> _pick() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path != null && mounted) setState(() => _path = path);
  }

  Future<void> _confirm() async {
    final path = _path;
    if (path == null) return;
    await VaultService.setVaultPath(path);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = _path;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(
                Icons.style_outlined,
                size: 40,
                color: AppColors.accent,
              ),
              const SizedBox(height: Space.lg),
              Text(
                'Keep Anki in step with your notes',
                style: AppTextStyles.title,
              ),
              const SizedBox(height: Space.md),
              Text(
                'Choose your Obsidian vault. Every note with a *** line '
                'becomes a card, and Interest keeps the cards matching the '
                'notes.',
                style: AppTextStyles.bodyMuted,
              ),
              const SizedBox(height: Space.xl),
              OutlinedButton.icon(
                onPressed: _pick,
                icon: const Icon(Icons.folder_open_rounded),
                label: Text(
                  path == null ? 'Choose vault folder' : 'Choose another',
                ),
              ),
              if (path != null) ...[
                const SizedBox(height: Space.md),
                Text(path, style: AppTextStyles.small),
              ],
              const Spacer(flex: 2),
              FilledButton(
                onPressed: path == null ? null : _confirm,
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
