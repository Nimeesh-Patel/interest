import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:people_tracker/features/anki/services/anki_connect_transport.dart';
import 'package:people_tracker/features/anki/services/anki_problem_note_scanner.dart';
import 'package:people_tracker/features/anki/services/anki_sync_service.dart';

const _usage = '''
Target selected vault Problem Notes through Interest's canonical Anki renderer.

Usage:
  dart run tool/sync_anki_notes.dart --vault <path> --file <relative-note.md> [--file ...] [--url <AnkiConnect URL>]

The command is intentionally file-bounded. Use Interest's UI for a whole-vault
sync. Each --file path must resolve inside the supplied vault.
''';

Future<void> main(List<String> args) async {
  String? vaultArgument;
  String? url;
  final requestedFiles = <String>[];

  for (var index = 0; index < args.length; index++) {
    switch (args[index]) {
      case '--vault':
        vaultArgument = _valueAfter(args, ++index, '--vault');
        break;
      case '--file':
        requestedFiles.add(_valueAfter(args, ++index, '--file'));
        break;
      case '--url':
        url = _valueAfter(args, ++index, '--url');
        break;
      case '--help':
      case '-h':
        stdout.write(_usage);
        return;
      default:
        _fail('Unknown argument: ${args[index]}');
    }
  }

  if (vaultArgument == null || requestedFiles.isEmpty) {
    _fail('Both --vault and at least one --file are required.');
  }

  final vault = Directory(vaultArgument).absolute;
  if (!await vault.exists()) _fail('Vault does not exist: ${vault.path}');

  final vaultRoot = p.canonicalize(vault.path);
  final wanted = <String>{};
  for (final argument in requestedFiles) {
    final candidate = p.canonicalize(
      p.isAbsolute(argument) ? argument : p.join(vault.path, argument),
    );
    if (!p.isWithin(vaultRoot, candidate)) {
      _fail('File escapes the vault: $argument');
    }
    wanted.add(candidate);
  }

  final scanned = await AnkiProblemNoteScanner.scan(vault.path);
  final selected =
      scanned
          .where((note) => wanted.contains(p.canonicalize(note.sourcePath)))
          .toList();
  final found = selected.map((note) => p.canonicalize(note.sourcePath)).toSet();
  final missing = wanted.difference(found);
  if (missing.isNotEmpty) {
    _fail(
      'Not syncable Problem Notes (missing, excluded, or without ***): '
      '${missing.join(', ')}',
    );
  }

  final transport = AnkiConnectTransport(url: url);
  if (!await transport.isAvailable()) {
    _fail(
      'AnkiConnect is not reachable at '
      '${url ?? AnkiConnectTransport.defaultUrl}',
    );
  }
  if (!await transport.requestPermission()) {
    _fail('AnkiConnect denied permission.');
  }

  final result = await AnkiSyncService.syncVault(
    transport,
    selected,
    vault.path,
  );
  stdout.writeln(
    'synced ${selected.length} notes '
    '(${result.added} added, ${result.updated} updated, ${result.failed} failed)',
  );
  for (final error in result.errors) {
    stderr.writeln(error);
  }
  if (result.failed > 0 || result.errors.isNotEmpty) exitCode = 1;
}

String _valueAfter(List<String> args, int index, String option) {
  if (index >= args.length) _fail('Missing value after $option.');
  return args[index];
}

Never _fail(String message) {
  stderr.writeln('error: $message');
  stderr.write(_usage);
  exit(2);
}
