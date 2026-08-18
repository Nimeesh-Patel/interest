import 'package:flutter/material.dart';

import '../../../core/vault_service.dart';
import '../../../shared/widgets/error_retry_state.dart';
import '../../../shared/widgets/progress.dart';
import '../services/inbox_storage_service.dart';
import 'task_file_screen.dart';

/// Direct, low-friction view over the persistent `Interesting/Inbox.md` file.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  String? _path;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _path = null;
      _error = null;
    });
    final vault = await VaultService.getVaultPath();
    if (!mounted) return;
    if (vault == null) {
      setState(() => _error = 'No vault is configured.');
      return;
    }
    final result = await InboxStorageService.ensureInbox(vault);
    if (!mounted) return;
    if (result.path == null) {
      setState(() => _error = result.error ?? 'Inbox could not be opened.');
      return;
    }
    setState(() => _path = result.path);
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return ErrorRetryState(message: error, onRetry: _load);
    }
    final path = _path;
    if (path == null) return const LoadingState();
    return TaskFileScreen(
      filePath: path,
      title: 'Inbox',
      embedded: true,
      inboxMode: true,
      emptyMessage: 'Inbox is empty.\nCapture anything below.',
      addHint: 'Add anything…',
    );
  }
}
