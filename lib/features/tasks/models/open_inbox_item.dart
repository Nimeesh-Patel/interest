class OpenInboxProseLine {
  final int line;
  final String text;

  const OpenInboxProseLine({required this.line, required this.text});

  Map<String, Object> toJson() => {'line': line, 'text': text};
}

/// Read-only projection of one unchecked checkbox in `Interesting/Inbox.md`.
///
/// It deliberately has no stable ID, kind, priority, or inferred status. The
/// checkbox text and attached prose remain the authored semantics; the rest is
/// transient retrieval context and provenance.
class OpenInboxItem {
  final String text;
  final int line;
  final int indentSpaces;
  final List<String> headings;
  final List<String> parentItems;
  final bool hasCompletedAncestor;
  final List<OpenInboxProseLine> attachedProse;

  const OpenInboxItem({
    required this.text,
    required this.line,
    required this.indentSpaces,
    required this.headings,
    required this.parentItems,
    required this.hasCompletedAncestor,
    required this.attachedProse,
  });

  Map<String, Object> toJson() => {
    'text': text,
    'state': 'open',
    'provenance': {
      'provider': 'interest',
      'source': 'Interesting/Inbox.md',
      'line': line,
      'indent_spaces': indentSpaces,
    },
    'context': {
      'headings': headings,
      'parent_items': parentItems,
      'has_completed_ancestor': hasCompletedAncestor,
      'attached_prose': attachedProse.map((line) => line.toJson()).toList(),
    },
  };
}

class OpenInboxQueryResult {
  static const providerName = 'interest';
  static const capabilityName = 'query_open_inbox';
  static const sourcePath = 'Interesting/Inbox.md';

  final String status;
  final String completeness;
  final String observedAt;
  final String? sourceModifiedAt;
  final List<String> errors;
  final List<String> limitations;
  final List<OpenInboxItem> records;

  const OpenInboxQueryResult({
    required this.status,
    required this.completeness,
    required this.observedAt,
    required this.sourceModifiedAt,
    required this.errors,
    required this.limitations,
    required this.records,
  });

  Map<String, Object?> toJson() => {
    'schema_version': 1,
    'provider': providerName,
    'capability': capabilityName,
    'status': status,
    'completeness': completeness,
    'scope': {
      'target': sourcePath,
      'included': [sourcePath],
      'outside_scope': {
        'handling': 'not_scanned',
        'description':
            'Every other vault file is outside this provider, including '
            'Interesting/Projects and other Markdown checkboxes.',
      },
    },
    'freshness': {
      'observed_at': observedAt,
      'source_modified_at': sourceModifiedAt,
      'basis':
          sourceModifiedAt == null
              ? status == 'indeterminate'
                  ? 'no coherent source timestamp was observed'
                  : 'source unavailable'
              : 'filesystem modification time at observation',
    },
    'records': records.map((record) => record.toJson()).toList(),
    'errors': errors,
    'limitations': limitations,
    'provenance': {'target': sourcePath},
  };
}
