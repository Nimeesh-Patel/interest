import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'core/vault_service.dart';
import 'core/vault_setup_screen.dart';
import 'features/sync/home_screen.dart';
import 'shared/constants/app_text_styles.dart';
import 'shared/constants/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final vaultPath = await VaultService.getVaultPath();
  runApp(InterestApp(initialVaultPath: vaultPath));
}

class InterestApp extends StatelessWidget {
  final String? initialVaultPath;

  const InterestApp({super.key, this.initialVaultPath});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Interest',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      home: _StoragePermissionGate(
        child:
            initialVaultPath == null
                ? const VaultSetupScreen()
                : const HomeScreen(),
      ),
    );
  }
}

/// Android needs All Files Access before the vault can be read at all.
class _StoragePermissionGate extends StatefulWidget {
  final Widget child;
  const _StoragePermissionGate({required this.child});

  @override
  State<_StoragePermissionGate> createState() => _StoragePermissionGateState();
}

class _StoragePermissionGateState extends State<_StoragePermissionGate>
    with WidgetsBindingObserver {
  bool? _granted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  Future<void> _checkPermission() async {
    if (!Platform.isAndroid) {
      setState(() => _granted = true);
      return;
    }
    final status = await Permission.manageExternalStorage.status;
    setState(() => _granted = status.isGranted);
  }

  @override
  Widget build(BuildContext context) {
    if (_granted == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_granted == true) return widget.child;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              const Icon(
                Icons.folder_open_rounded,
                size: 40,
                color: AppColors.accent,
              ),
              const SizedBox(height: Space.lg),
              Text('Allow access to your vault', style: AppTextStyles.title),
              const SizedBox(height: Space.md),
              Text(
                'Interest reads your Obsidian notes to build Anki cards. '
                'Android calls this All Files Access. Turn it on for '
                'Interest, then come back.',
                style: AppTextStyles.bodyMuted,
              ),
              const Spacer(flex: 2),
              FilledButton(
                onPressed: () => Permission.manageExternalStorage.request(),
                child: const Text('Open Android settings'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
