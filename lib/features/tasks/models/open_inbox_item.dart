class OpenInboxProseLine {
  final int line;
  final String text;

  const OpenInboxProseLine({required this.line, required this.text});

  Map<String, Object> toJson() => {'line': line, 'text': text};
}

/// Complete, coherent evidence from `Interesting/Inbox.md`.
///
/// [text] excludes an optional UTF-8 BOM so Markdown parsing is not changed by
/// an encoding marker. [hasUtf8Bom] records that marker separately, while all
/// authored text and line endings remain unchanged.
class OpenInboxDocument {
  final String text;
  final bool hasUtf8Bom;
  final int byteLength;
  final String locator;

  const OpenInboxDocument({
    required this.text,
    required this.hasUtf8Bom,
    required this.byteLength,
    required this.locator,
  });

  Map<String, Object> toJson() => {
    'kind': 'markdown_document',
    'text': text,
    'encoding': 'utf-8',
    'utf8_bom': hasUtf8Bom,
    'byte_length': byteLength,
    'line_endings': 'preserved',
    'locator': locator,
    'provenance': {
      'provider': OpenInboxQueryResult.providerName,
      'source': OpenInboxQueryResult.sourcePath,
    },
  };
}

/// Non-exhaustive read-only hint derived from one unchecked checkbox.
///
/// It deliberately has no stable ID, priority, or inferred status. Its `kind`
/// identifies this projection, not an authored item type. The checkbox text and
/// attached prose remain the authored semantics; the rest is transient
/// retrieval context and provenance. The complete document, not this
/// projection, is the provider's authoritative evidence.
class OpenInboxItem {
  final String text;
  final int line;
  final int indentSpaces;
  final List<String> headings;
  final List<String> parentItems;
  final bool hasCompletedAncestor;
  final List<OpenInboxProseLine> attachedProse;
  final String locator;

  const OpenInboxItem({
    required this.text,
    required this.line,
    required this.indentSpaces,
    required this.headings,
    required this.parentItems,
    required this.hasCompletedAncestor,
    required this.attachedProse,
    required this.locator,
  });

  Map<String, Object> toJson() => {
    'kind': 'unchecked_checkbox_hint',
    'text': text,
    'state': 'open',
    'locator': locator,
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

/// Optional checkbox projection with an outcome independent of document read.
class OpenInboxDerivedHints {
  final String status;
  final String completeness;
  final List<String> errors;
  final List<OpenInboxItem> records;

  const OpenInboxDerivedHints({
    required this.status,
    required this.completeness,
    required this.errors,
    required this.records,
  });

  Map<String, Object> toJson() => {
    'status': status,
    'completeness': completeness,
    'projection': {
      'kind': 'unchecked_checkbox',
      'exhaustive': false,
      'authoritative_evidence': 'records',
    },
    'records': records.map((hint) => hint.toJson()).toList(),
    'errors': errors,
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
  final List<OpenInboxDocument> records;
  final OpenInboxDerivedHints derivedHints;

  const OpenInboxQueryResult({
    required this.status,
    required this.completeness,
    required this.observedAt,
    required this.sourceModifiedAt,
    required this.errors,
    required this.limitations,
    required this.records,
    required this.derivedHints,
  });

  bool get isSuccessful => status == 'complete' || status == 'partial';

  Map<String, Object?> toJson() => {
    'schema_version': 2,
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
    'derived_hints': derivedHints.toJson(),
    'errors': errors,
    'limitations': limitations,
    'provenance': {'target': sourcePath},
  };
}
