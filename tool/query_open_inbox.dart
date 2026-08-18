import 'dart:convert';
import 'dart:io';

import 'package:people_tracker/features/tasks/services/open_inbox_query_service.dart';

const _usage = '''
Read Interest's canonical Inbox Markdown and derived checkbox hints.

Usage:
  dart run tool/query_open_inbox.dart --vault <path> [--pretty]

Only Interesting/Inbox.md is in scope. records contains its complete Markdown
document; derived_hints contains non-exhaustive checkbox projections.
''';

Future<void> main(List<String> args) async {
  String? vaultPath;
  var pretty = false;

  for (var index = 0; index < args.length; index++) {
    switch (args[index]) {
      case '--vault':
        vaultPath = _valueAfter(args, ++index, '--vault');
        break;
      case '--pretty':
        pretty = true;
        break;
      case '--help':
      case '-h':
        stdout.add(utf8.encode(_usage));
        await stdout.flush();
        return;
      default:
        _fail('Unknown argument: ${args[index]}');
    }
  }

  if (vaultPath == null) _fail('--vault is required.');

  final result = await OpenInboxQueryService.query(vaultPath);
  final payload =
      pretty
          ? const JsonEncoder.withIndent('  ').convert(result.toJson())
          : jsonEncode(result.toJson());
  stdout.add(utf8.encode('$payload\n'));
  await stdout.flush();
  if (!result.isSuccessful) exitCode = 1;
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
