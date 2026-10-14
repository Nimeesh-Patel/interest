import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as p;
import 'package:people_tracker/features/anki/services/anki_sync_lock.dart';

/// Disposable process-level regression check; never opens a real vault or Anki.
Future<void> main(List<String> args) async {
  if (args.length == 2) {
    final lease = await AnkiSyncLock.acquire(args[1]);
    stdout.writeln(lease == null ? 'BLOCKED' : 'ACQUIRED');
    if (lease != null && args[0] == '--hold') {
      stdin.readLineSync();
    }
    await lease?.release();
    return;
  }
  final root = await Directory.systemTemp.resolveSymbolicLinks();
  final vault = await Directory(root).createTemp('interest_sync_lock_probe_');
  final packages = await Isolate.packageConfig;
  final command = [
    if (packages != null) '--packages=${packages.toFilePath()}',
    Platform.script.toFilePath(),
  ];
  Process? holder;
  try {
    holder = await Process.start(Platform.resolvedExecutable, [
      ...command,
      '--hold',
      vault.path,
    ]);
    final lines = StreamIterator(
      holder.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    if (!await lines.moveNext().timeout(const Duration(seconds: 10)) ||
        lines.current != 'ACQUIRED') {
      throw StateError('Holder did not acquire the disposable vault lease');
    }
    await lines.cancel();
    final contender = await Process.run(Platform.resolvedExecutable, [
      ...command,
      '--try',
      vault.path,
    ]);
    if (contender.exitCode != 0 || '${contender.stdout}'.trim() != 'BLOCKED') {
      throw StateError(
        'A second process was not excluded: ${contender.stderr}',
      );
    }
    holder.stdin.writeln();
    await holder.stdin.close();
    if (await holder.exitCode.timeout(const Duration(seconds: 10)) != 0) {
      throw StateError('Holder failed');
    }
    final next = await AnkiSyncLock.acquire(vault.path);
    if (next == null) {
      throw StateError('The released lease could not be acquired again');
    }
    await next.release();
    stdout.writeln(
      'PASS: process exclusion and release against a disposable vault',
    );
  } finally {
    holder?.kill();
    final target = await vault.resolveSymbolicLinks();
    if (!p.isWithin(root, target) ||
        !p.basename(target).startsWith('interest_sync_lock_probe_')) {
      throw StateError('Refused cleanup outside the owned fixture directory');
    }
    await vault.delete(recursive: true);
  }
}
