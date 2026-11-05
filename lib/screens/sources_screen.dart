import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/integrations_config_service.dart';
import '../core/vault_service.dart';
import '../shared/utils/obsidian_launcher.dart';

import '../features/anki/services/anki_connect_transport.dart';
import '../features/anki/services/anki_sync_controller.dart';
import '../features/anki/services/anki_sync_runner.dart';
import '../features/anki/services/anki_state_capture_service.dart';
import '../shared/constants/app_text_styles.dart';
import '../shared/constants/app_theme.dart';
import '../shared/widgets/list_row.dart';
import '../shared/widgets/confirm_dialog.dart';
import '../shared/widgets/progress.dart';
import '../shared/widgets/snack.dart';

class SourcesScreen extends StatefulWidget {
  const SourcesScreen({super.key});

  @override
  State<SourcesScreen> createState() => _SourcesScreenState();
}

class _SourcesScreenState extends State<SourcesScreen> {
  // One flag per Anki row, but the two syncs are mutually exclusive: both
  // write anki_note_id back to the same vault files.
  bool _syncingAnkiDroid = false;
  bool _syncingAnkiConnect = false;
  bool _capturingAnki = false;

  bool get _ankiBusy =>
      _syncingAnkiDroid || _syncingAnkiConnect || _capturingAnki;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sources')),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            _SourceRow(
              icon: Icons.folder_open,
              name: 'Obsidian',
              description: 'Open the vault',
              meta: 'external app',
              onTap: () => launchObsidianApp(context),
            ),
            // AnkiDroid: the interest://sync-anki deep link triggers the same
            // sync, but this row is a no-plugin manual trigger. Android only.
            if (Platform.isAndroid)
              _SourceRow(
                icon: Icons.style,
                name: 'AnkiDroid',
                description:
                    _syncingAnkiDroid
                        ? 'Syncing problem notes…'
                        : 'Push problem notes to AnkiDroid',
                meta: 'Flashcard sync',
                busy: _syncingAnkiDroid,
                onTap: _ankiBusy ? null : _syncAnkiDroid,
              ),
            if (Platform.isAndroid)
              _SourceRow(
                icon: Icons.file_download_outlined,
                name: 'Capture Anki state',
                description:
                    _capturingAnki
                        ? 'Reading card states…'
                        : 'Due now, answered today and new cards',
                meta: 'Export snapshot',
                busy: _capturingAnki,
                onTap: _ankiBusy ? null : _captureAnkiState,
              ),
            _SourceRow(
              icon: Icons.desktop_windows,
              name: 'Anki desktop',
              description:
                  _syncingAnkiConnect
                      ? 'Syncing problem notes…'
                      : 'Push problem notes via AnkiConnect',
              meta: 'Flashcard sync',
              busy: _syncingAnkiConnect,
              onTap: _ankiBusy ? null : _syncAnkiConnect,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _captureAnkiState() async {
    if (_ankiBusy) return;
    setState(() => _capturingAnki = true);
    try {
      final service = AnkiStateCaptureService();
      final capture = await service.capture();
      if (!mounted) return;
      final observations = capture['records'] as List;
      const labels = {
        'is:due': 'Due now',
        'rated:1': 'Answered today',
        'is:new': 'New cards',
      };
      final summary = observations
          .map((raw) {
            final item = raw as Map;
            final label = labels[item['query']] ?? item['query'];
            return item['status'] == 'unavailable'
                ? '$label: unavailable'
                : '$label: ${(item['cards'] as List).length} of ${item['total']}';
          })
          .join('\n');
      if (capture['status'] != 'complete') {
        final proceed = await showConfirmDialog(
          context,
          title:
              capture['status'] == 'unavailable'
                  ? 'Card state unavailable'
                  : 'Partial capture',
          message: '$summary\n\nExport this capture with its limits recorded?',
          confirmLabel: 'Export',
          isDestructive: false,
        );
        if (!proceed || !mounted) return;
      }
      final saved = await service.save(capture);
      if (!mounted) return;
      switch (saved['status']) {
        case 'cancelled':
          showSnack(context, 'Export cancelled');
        case 'written_unverified':
          showSnack(
            context,
            'Capture written, but the destination could not verify it. Check the chosen file before using it.',
            duration: const Duration(seconds: 8),
          );
        case 'verified':
          showSnack(
            context,
            capture['status'] == 'complete'
                ? 'Anki state exported and verified'
                : 'Partial Anki state exported and verified; limits are recorded in the file',
          );
      }
    } catch (error) {
      if (mounted) {
        showSnack(context, 'Anki state capture failed: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _capturingAnki = false);
    }
  }

  Future<void> _syncAnkiDroid() async {
    if (_ankiBusy) return;
    await runAnkiDroidSync(
      context,
      onBusy: (busy) {
        if (mounted) setState(() => _syncingAnkiDroid = busy);
      },
    );
  }

  Future<void> _syncAnkiConnect() async {
    if (_ankiBusy) return;
    setState(() => _syncingAnkiConnect = true);
    try {
      final vaultPath = await VaultService.getVaultPath();
      if (!mounted) return;
      if (vaultPath == null) {
        showSnack(context, 'No vault configured');
        return;
      }
      final config = await IntegrationsConfigService.load(vaultPath);
      final transport = AnkiConnectTransport(url: config.ankiConnectUrl);
      if (!await transport.isAvailable()) {
        if (mounted) {
          showSnack(
            context,
            'Anki desktop not reachable — is Anki running with AnkiConnect installed?',
          );
        }
        return;
      }
      if (!mounted) return;
      if (!await transport.requestPermission()) {
        if (mounted) showSnack(context, 'AnkiConnect denied the connection');
        return;
      }
      final result = await AnkiSyncController.sync(transport);
      if (mounted) showAnkiSyncResult(context, transport, result);
    } catch (error) {
      if (mounted) showSnack(context, 'Sync could not start: $error');
    } finally {
      if (mounted) setState(() => _syncingAnkiConnect = false);
    }
  }
}

class _SourceRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final String description;
  final String meta;
  final VoidCallback? onTap;

  /// While true the row is dimmed, untappable, and shows a spinner trailing.
  final bool busy;

  const _SourceRow({
    required this.icon,
    required this.name,
    required this.description,
    required this.meta,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final tappable = onTap != null && !busy;
    return ListRow(
      onTap: tappable ? onTap : null,
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: tappable ? AppColors.textSecondary : AppColors.textTertiary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: AppTextStyles.entityName.copyWith(
                    color:
                        tappable
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(description, style: AppTextStyles.bodySmall),
                    ),
                    Text(meta, style: AppTextStyles.metaMuted),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (busy)
            const InlineSpinner(size: 14)
          else if (tappable)
            const Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: AppColors.textTertiary,
            ),
        ],
      ),
    );
  }
}
