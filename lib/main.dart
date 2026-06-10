import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'screens/home_screen.dart';
import 'core/vault_setup_screen.dart';
import 'core/vault_service.dart';
import 'shared/constants/app_theme.dart';
import 'shared/widgets/progress.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final vaultPath = await VaultService.getVaultPath();
  runApp(EntityTrackerApp(initialVaultPath: vaultPath));
}

class EntityTrackerApp extends StatelessWidget {
  final String? initialVaultPath;

  const EntityTrackerApp({super.key, this.initialVaultPath});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Entity Tracker',
      theme: buildAppTheme(),
      darkTheme: buildAppTheme(),
      themeMode: ThemeMode.dark,
      home: _StoragePermissionGate(
        child: initialVaultPath == null ? const VaultSetupScreen() : const HomeScreen(),
      ),
    );
  }
}

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
      return const Scaffold(body: LoadingState());
    }
    if (_granted == true) return widget.child;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Permission Required'),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This app needs "All Files Access" to read and write Markdown notes '
              'in your Obsidian vault folder.',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            const Text(
              'Tap "Open Settings", enable "All Files Access" for this app, '
              'then return here.',
              style: TextStyle(fontSize: 14),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Permission.manageExternalStorage.request(),
                child: const Text('Open Settings'),
              ),
            ),
          ],
        ),
      )),
    );
  }
}
