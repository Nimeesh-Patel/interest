import 'package:flutter/material.dart';

import '../../../shared/constants/app_text_styles.dart';
import '../../../shared/widgets/snack.dart';
import 'anki_sync_service.dart';
import 'anki_transport.dart';

/// Reports an [AnkiSyncResult]: a scrollable failures dialog when notes failed
/// with messages, otherwise a one-line summary snackbar. A null result means
/// no vault was configured.
void showAnkiSyncResult(
    BuildContext context, AnkiTransport transport, AnkiSyncResult? result) {
  if (result == null) {
    showSnack(context, 'No vault configured');
    return;
  }

  final total = result.added + result.updated;

  if (result.failed > 0 && result.errors.isNotEmpty) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title:
            Text('${result.failed} note${result.failed == 1 ? '' : 's'} failed'),
        content: SingleChildScrollView(
          child:
              Text(result.errors.join('\n\n'), style: AppTextStyles.bodySmall),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } else {
    final msg = result.failed == 0
        ? 'Synced $total problem notes to ${transport.displayName} (${result.added} added, ${result.updated} updated)'
        : '${result.failed} notes failed';
    showSnack(context, msg);
  }
}
