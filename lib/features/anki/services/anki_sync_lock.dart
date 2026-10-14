import 'dart:io';
import 'package:path/path.dart' as p;

/// One mutation lease per physical vault, shared by UI, deep link and CLI.
/// The empty lock file is retained so processes cannot lock rival file identities.
class AnkiSyncLock {
  static final _active = <String>{};
  final String _key;
  final RandomAccessFile _file;
  AnkiSyncLock._(this._key, this._file);

  static Future<AnkiSyncLock?> acquire(String vaultPath) async {
    final resolved = await Directory(vaultPath).resolveSymbolicLinks();
    final key = Platform.isWindows ? resolved.toLowerCase() : resolved;
    if (!_active.add(key)) return null;
    RandomAccessFile? file;
    try {
      final path = File(
        p.join(resolved, 'Interesting', 'System', '.anki-sync.lock'),
      );
      await path.parent.create(recursive: true);
      file = await path.open(mode: FileMode.append);
      await file.lock(FileLock.exclusive);
      return AnkiSyncLock._(key, file);
    } on FileSystemException {
      await file?.close();
      _active.remove(key);
      return null;
    } catch (_) {
      await file?.close();
      _active.remove(key);
      rethrow;
    }
  }

  Future<void> release() async {
    try {
      await _file.unlock();
    } finally {
      try {
        await _file.close();
      } finally {
        _active.remove(_key);
      }
    }
  }
}
