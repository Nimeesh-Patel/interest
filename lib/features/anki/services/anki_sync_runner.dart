import 'package:flutter/material.dart';

import '../../../shared/constants/app_text_styles.dart';
import '../../../shared/constants/app_theme.dart';
import '../../../shared/widgets/snack.dart';
import 'anki_sync_controller.dart';
import 'anki_sync_service.dart';
import 'ankidroid_transport.dart';
import 'anki_transport.dart';

/// Runs the whole-vault AnkiDroid push (availability + permission + sync) and
/// reports the outcome through [showAnkiSyncResult]. Shared by the Sources
/// screen's AnkiDroid row and the `interest://sync-anki` deep link so both
/// behave identically. [onBusy] lets a caller reflect progress in its own UI.
Future<void> runAnkiDroidSync(
  BuildContext context, {
  void Function(bool busy)? onBusy,
}) async {
  onBusy?.call(true);
  try {
    final transport = AnkiDroidTransport();

    final available = await transport.isAvailable();
    if (!context.mounted) return;
    if (!available) {
      showSnack(context, 'AnkiDroid not installed');
      return;
    }

    final granted = await transport.requestPermission();
    if (!context.mounted) return;
    if (!granted) {
      showSnack(context, 'Permission denied');
      return;
    }

    final result = await AnkiSyncController.sync(transport);
    if (!context.mounted) return;
    await showAnkiSyncResult(context, transport, result);
  } finally {
    onBusy?.call(false);
  }
}

/// Reports an [AnkiSyncResult]: a scrollable failures dialog when notes failed
/// with messages, otherwise a one-line summary snackbar. A null result means
/// no vault was configured. Cards that need Nimeesh's decision (orphans whose
/// notes are gone, linked notes whose cards are missing) are then offered for
/// confirmation, applied through a fresh discovery, and reported in turn.
Future<void> showAnkiSyncResult(
  BuildContext context,
  AnkiTransport transport,
  AnkiSyncResult? result,
) async {
  if (result == null) {
    showSnack(context, 'No vault configured');
    return;
  }
  await _report(context, transport, result);
  if (!context.mounted || !result.needsDecision) return;

  // Permission is granted per card: each dialog shows one card and stands
  // alone, so a decision about one card never covers another.
  final retire = <AnkiOrphanCard>[];
  final orphans = result.orphans;
  for (var i = 0; i < orphans.length; i++) {
    final card = orphans[i];
    final remove = await _confirmCard(
      context,
      heading: 'Remove card${_position(i, orphans.length)}',
      title: card.title,
      problem: card.problem,
      conjecture: card.conjecture,
      explanation: 'This card has no Obsidian note.',
      confirmLabel: 'Remove',
      cancelLabel: 'Keep',
      destructive: true,
    );
    if (!context.mounted) return;
    if (remove) retire.add(card);
  }
  final recreate = <AnkiMissingCard>[];
  final missing = result.missing;
  for (var i = 0; i < missing.length; i++) {
    final item = missing[i];
    final again = await _confirmCard(
      context,
      heading: 'Re-create card${_position(i, missing.length)}',
      title: item.title,
      problem: item.problem,
      conjecture: item.conjecture,
      explanation: "This note's card is missing from ${transport.displayName}.",
      confirmLabel: 'Re-create',
      cancelLabel: 'Not now',
      destructive: false,
    );
    if (!context.mounted) return;
    if (again) recreate.add(item);
  }
  if (retire.isEmpty && recreate.isEmpty) return;
  final resolved = await AnkiSyncController.resolve(
    transport,
    recreate: recreate,
    retire: retire,
  );
  if (!context.mounted) return;
  if (resolved == null) {
    showSnack(context, 'No vault configured');
  } else {
    await _report(context, transport, resolved);
  }
}

String _position(int index, int count) =>
    count > 1 ? ' ${index + 1} of $count' : '';

/// One card per dialog: its note title, its problem side, and its conjecture
/// side cut to a readable length, then why the decision is needed.
Future<bool> _confirmCard(
  BuildContext context, {
  required String heading,
  required String title,
  required String problem,
  required String conjecture,
  required String explanation,
  required String confirmLabel,
  required String cancelLabel,
  required bool destructive,
}) async {
  const conjectureLimit = 300;
  String shown(String text) => text.isEmpty ? '(empty)' : text;
  final cut =
      conjecture.length > conjectureLimit
          ? '${conjecture.substring(0, conjectureLimit).trimRight()}…'
          : conjecture;
  Widget section(String label, String text) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.metaMuted),
        const SizedBox(height: 4),
        Text(shown(text), style: AppTextStyles.bodyMedium),
      ],
    ),
  );
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(heading, style: AppTextStyles.metaMuted),
              const SizedBox(height: 4),
              Text(title, style: AppTextStyles.appTitle),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(explanation, style: AppTextStyles.bodyMedium),
                section('Problem', problem),
                section('Conjecture', cut),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(cancelLabel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                confirmLabel,
                style:
                    destructive
                        ? const TextStyle(color: AppColors.destructive)
                        : null,
              ),
            ),
          ],
        ),
  );
  return confirmed ?? false;
}

Future<void> _report(
  BuildContext context,
  AnkiTransport transport,
  AnkiSyncResult result,
) async {
  final removed = result.retired + result.duplicatesRetired;
  final summary = StringBuffer(
    '${result.added} added, ${result.updated} updated, '
    '${result.unchanged} unchanged, $removed removed',
  );
  if (result.duplicatesRetired > 0) {
    summary.write(' (${result.duplicatesRetired} duplicates)');
  }
  if (!result.isSuccessful) {
    summary.write(', ${result.failed} failed');
    if (result.skipped > 0) summary.write(', ${result.skipped} not attempted');
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: Text(
              result.completed
                  ? 'Sync finished with errors'
                  : 'Sync did not complete',
            ),
            content: SingleChildScrollView(
              child: Text(
                '$summary\n\n${result.errors.join('\n\n')}',
                style: AppTextStyles.bodySmall,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  } else {
    showSnack(context, '${transport.displayName}: $summary');
  }
}
