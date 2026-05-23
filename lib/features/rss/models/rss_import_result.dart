class ImportResult {
  final int created;
  final int updated;
  final int skipped;
  final String? error;

  const ImportResult({
    required this.created,
    required this.updated,
    required this.skipped,
    this.error,
  });

  String get summary => error != null
      ? 'Error: $error'
      : '$created created, $updated updated, $skipped skipped';
}
