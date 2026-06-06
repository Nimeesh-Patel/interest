import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../core/vault_service.dart';
import '../../../shared/constants/app_text_styles.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/widgets/section_header.dart';
import '../models/resurface_note.dart';
import '../services/resurface_service.dart';

/// Async backlinks panel. Shows after load; renders nothing until ready.
/// Use [key: ValueKey(noteFilePath)] in list contexts to reset on note change.
class BacklinksSection extends StatefulWidget {
  final String noteFilePath;
  final Future<void> Function(String targetName) onNavigateToNote;

  const BacklinksSection({
    super.key,
    required this.noteFilePath,
    required this.onNavigateToNote,
  });

  @override
  State<BacklinksSection> createState() => _BacklinksSectionState();
}

class _BacklinksSectionState extends State<BacklinksSection> {
  List<ResurfaceNote>? _backlinks; // null = still loading

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BacklinksSection old) {
    super.didUpdateWidget(old);
    if (old.noteFilePath != widget.noteFilePath) {
      setState(() => _backlinks = null);
      _load();
    }
  }

  Future<void> _load() async {
    final vaultPath = await VaultService.getVaultPath();
    if (!mounted || vaultPath == null) return;
    final backlinks =
        await ResurfaceService.getBacklinks(vaultPath, widget.noteFilePath);
    if (!mounted) return;
    setState(() => _backlinks = backlinks);
  }

  @override
  Widget build(BuildContext context) {
    final backlinks = _backlinks;
    if (backlinks == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 32),
        const Divider(thickness: 1, color: AppColors.border),
        SectionHeader(title: 'Backlinks'),
        if (backlinks.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 4),
            child: Text(
              'No backlinks',
              style:
                  AppTextStyles.bodySmall.copyWith(color: AppColors.textTertiary),
            ),
          )
        else
          for (final note in backlinks)
            InkWell(
              onTap: () => widget
                  .onNavigateToNote(p.basenameWithoutExtension(note.sourceFile)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  p.basenameWithoutExtension(note.sourceFile),
                  style: AppTextStyles.entityName.copyWith(
                    color: AppColors.accent,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.accent,
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
