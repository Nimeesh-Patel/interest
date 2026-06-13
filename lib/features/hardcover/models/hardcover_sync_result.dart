class HardcoverSyncResult {
  final int importedFromHardcover;
  final int updatedFromHardcover;
  final int pushedToHardcover;
  final int linkedToHardcover;
  final int skipped;
  final String? error;

  const HardcoverSyncResult({
    this.importedFromHardcover = 0,
    this.updatedFromHardcover = 0,
    this.pushedToHardcover = 0,
    this.linkedToHardcover = 0,
    this.skipped = 0,
    this.error,
  });

  String get summary {
    if (error != null) return 'Error: $error';
    final parts = <String>[];
    if (importedFromHardcover > 0) {
      parts.add('$importedFromHardcover imported');
    }
    if (updatedFromHardcover > 0) {
      parts.add('$updatedFromHardcover updated from Hardcover');
    }
    if (linkedToHardcover > 0) {
      parts.add('$linkedToHardcover linked');
    }
    if (pushedToHardcover > 0) {
      parts.add('$pushedToHardcover pushed to Hardcover');
    }
    if (skipped > 0) parts.add('$skipped unchanged');
    if (parts.isEmpty) return 'Nothing to sync.';
    return parts.join(' · ');
  }
}
