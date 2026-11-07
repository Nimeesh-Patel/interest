import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/vault_service.dart';
import '../../shared/constants/app_text_styles.dart';
import '../../shared/constants/app_theme.dart';
import '../../shared/widgets/snack.dart';
import '../anki/services/anki_state_capture_service.dart';
import 'sync_memory.dart';
import 'sync_target.dart';

/// Everything that decides what a sync does, visible in one place. Pops with
/// `true` when a change means the home screen should look again.
class SettingsScreen extends StatefulWidget {
  final SyncTarget target;
  const SettingsScreen({super.key, required this.target});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _vault;
  TargetReadiness? _readiness;
  int _kept = 0;
  bool _changed = false;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vault = await VaultService.getVaultPath();
    final kept = await SyncMemory.keptCards();
    final readiness = await widget.target.prepare();
    if (!mounted) return;
    setState(() {
      _vault = vault;
      _kept = kept.length;
      _readiness = readiness;
    });
  }

  Future<void> _changeVault() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || !mounted) return;
    await VaultService.setVaultPath(path);
    setState(() {
      _vault = path;
      _changed = true;
    });
  }

  Future<void> _askAgain() async {
    await SyncMemory.clearKept();
    setState(() {
      _kept = 0;
      _changed = true;
    });
  }

  Future<void> _exportState() async {
    setState(() => _exporting = true);
    try {
      final service = AnkiStateCaptureService();
      final capture = await service.capture();
      if (!mounted) return;
      if (capture['status'] != 'complete') {
        final proceed = await showDialog<bool>(
          context: context,
          builder:
              (dialog) => AlertDialog(
                title: const Text('Some card state was unavailable'),
                content: const Text(
                  'The export will record exactly what could and could not be read.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('Export anyway'),
                  ),
                ],
              ),
        );
        if (proceed != true) return;
      }
      final saved = await service.save(capture);
      if (!mounted) return;
      showSnack(context, switch (saved['status']) {
        'cancelled' => 'Export cancelled',
        'verified' => 'Anki state exported',
        _ =>
          'Written, but the file could not be verified. Check it before use.',
      });
    } catch (error) {
      if (mounted) showSnack(context, 'Export failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.target.name;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.xxl),
            children: [
              const _Section('Vault'),
              _Item(
                icon: Icons.folder_outlined,
                title: _vault == null ? 'No folder chosen' : _name(_vault!),
                detail: _vault ?? 'Choose the folder Obsidian opens.',
                action: TextButton(
                  onPressed: _changeVault,
                  child: const Text('Change'),
                ),
              ),
              const _Section('Anki'),
              _Item(
                icon: Icons.style_outlined,
                title: 'Cards go to $target',
                detail: switch (_readiness) {
                  null => 'Checking access',
                  TargetReadiness.ready => 'Connected and allowed',
                  TargetReadiness.notInstalled => '$target isn\'t available',
                  TargetReadiness.permissionDenied => 'Access not allowed yet',
                },
                detailColor: switch (_readiness) {
                  TargetReadiness.ready => AppColors.success,
                  null => null,
                  _ => AppColors.warning,
                },
                action:
                    _readiness == TargetReadiness.permissionDenied
                        ? TextButton(
                          onPressed: _load,
                          child: const Text('Allow'),
                        )
                        : null,
              ),
              _Item(
                icon: Icons.bookmark_border_rounded,
                title:
                    _kept == 0
                        ? 'No kept cards'
                        : _kept == 1
                        ? '1 card kept without a note'
                        : '$_kept cards kept without a note',
                detail: 'Cards you chose to keep are not asked about again.',
                action:
                    _kept == 0
                        ? null
                        : TextButton(
                          onPressed: _askAgain,
                          child: const Text('Ask again'),
                        ),
              ),
              const _Section('How notes become cards'),
              const _Rule(
                'A note with a *** line becomes one card: the problem above it, '
                'the conjecture below.',
              ),
              const _Rule(
                'A note with collection: in its properties never becomes a card.',
              ),
              const _Rule(
                'category: picks the deck. Without it, the card goes to Default.',
              ),
              const _Rule(
                'Templates, attachments, trash and the memory folder are skipped.',
              ),
              if (Platform.isAndroid) ...[
                const _Section('Perspirator'),
                _Item(
                  icon: Icons.download_outlined,
                  title: 'Export Anki state',
                  detail:
                      'Save what is due, answered today and new as a file '
                      'Perspirator can read.',
                  action:
                      _exporting
                          ? const Padding(
                            padding: EdgeInsets.all(Space.md),
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                          : TextButton(
                            onPressed: _exportState,
                            child: const Text('Export'),
                          ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _name(String path) =>
      path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last;
}

class _Section extends StatelessWidget {
  final String title;
  const _Section(this.title);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.xl,
      Space.gutter,
      Space.sm,
    ),
    child: Text(
      title,
      style: AppTextStyles.smallStrong.copyWith(color: AppColors.accent),
    ),
  );
}

class _Item extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Color? detailColor;
  final Widget? action;

  const _Item({
    required this.icon,
    required this.title,
    required this.detail,
    this.detailColor,
    this.action,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Space.gutter,
      vertical: Space.md,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, color: AppColors.inkMuted),
        ),
        const SizedBox(width: Space.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppTextStyles.body),
              const SizedBox(height: 2),
              Text(
                detail,
                style: AppTextStyles.bodyMuted.copyWith(
                  fontSize: 14,
                  color: detailColor,
                ),
              ),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: Space.sm), action!],
      ],
    ),
  );
}

class _Rule extends StatelessWidget {
  final String text;
  const _Rule(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Space.gutter,
      Space.xs,
      Space.gutter,
      Space.sm,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 9, right: Space.md, left: 8),
          child: SizedBox.square(
            dimension: 5,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.inkFaint,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        Expanded(child: Text(text, style: AppTextStyles.bodyMuted)),
      ],
    ),
  );
}
