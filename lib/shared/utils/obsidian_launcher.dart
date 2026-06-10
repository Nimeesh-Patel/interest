import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/snack.dart';

/// Launches the Obsidian app (not a specific note). Shows a snackbar if
/// Obsidian is not installed.
Future<void> launchObsidianApp(BuildContext context) async {
  final launched = await launchUrl(
    Uri.parse('obsidian://'),
    mode: LaunchMode.externalApplication,
  );
  if (!launched && context.mounted) {
    showSnack(context, 'Obsidian is not installed');
  }
}
