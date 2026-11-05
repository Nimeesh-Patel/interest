import 'dart:convert';

import 'package:flutter/services.dart';

import 'ankidroid_transport.dart';

/// A dated native observation. Anki retains scheduling authority; this neither
/// invokes the sync engine nor predicts the user's eventual review session.
class AnkiStateCaptureService {
  static const queries = ['is:due', 'rated:1', 'is:new'];
  static const defaultLimit = 200;
  static const _stateColumns = [
    'deck_id',
    'original_deck_id',
    'type',
    'queue',
    'due',
    'original_due',
    'interval',
    'reps',
    'lapses',
  ];
  static const _anki = MethodChannel('dev.interest.app/ankidroid');
  static const _export = MethodChannel('dev.interest.app/anki-state-export');
  final DateTime Function() _now;

  AnkiStateCaptureService({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  Future<Map<String, Object?>> capture({int limit = defaultLimit}) async {
    if (limit < 1 || limit > 1000) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 1000');
    }
    final started = _now();
    final transport = AnkiDroidTransport();
    if (!await transport.isAvailable()) {
      throw StateError('AnkiDroid is not available');
    }
    if (!await transport.requestPermission()) {
      throw StateError('AnkiDroid permission was not granted');
    }
    final errors = <Object?>[];
    String? version;
    try {
      version = await _anki.invokeMethod<String>('getAnkiDroidVersion');
      if (version == null) throw const FormatException('No installed version');
    } catch (error) {
      errors.add({'stage': 'version', 'message': error.toString()});
    }
    final observations = <Map<String, Object?>>[];
    for (final query in queries) {
      try {
        final raw = await _anki.invokeMethod<Object>('queryCardState', {
          'query': query,
          'limit': limit,
        });
        observations.add(_observation(raw, query));
      } catch (error) {
        observations.add({
          'query': query,
          'status': 'unavailable',
          'observed_at_ms': _now().millisecondsSinceEpoch,
          'total': null,
          'cards': <Object?>[],
          'errors': [
            {'stage': 'query', 'message': error.toString()},
          ],
        });
      }
    }
    final complete = observations.every((o) => o['status'] == 'complete');
    final observed = observations.any((o) => o['status'] != 'unavailable');
    return {
      'provider': 'ankidroid',
      'capability': 'card-state',
      'status':
          complete && errors.isEmpty
              ? 'complete'
              : observed
              ? 'partial'
              : 'unavailable',
      'scope': {
        'queries': queries,
        'limit_per_query': limit,
        'anki_version': version,
        'collection_identity': null,
        'native_search_cost_bounded': false,
        'unobserved': [
          'future review order or session membership',
          'review-event history',
          'collection identity and Anki day boundary',
        ],
      },
      'freshness': {
        'started_at': started.toUtc().toIso8601String(),
        'finished_at': _now().toUtc().toIso8601String(),
        'timezone_offset_minutes': started.timeZoneOffset.inMinutes,
        'live': false,
        'atomic': false,
      },
      'records': observations,
      'errors': errors,
    };
  }

  /// The native chooser returns its actual content URI and distinguishes a
  /// read-back-verified write from a write its document provider cannot verify.
  Future<Map<String, Object?>> save(Map<String, Object?> capture) async {
    final bytes = Uint8List.fromList(
      utf8.encode('${const JsonEncoder.withIndent('  ').convert(capture)}\n'),
    );
    final stamp = _now().toUtc().toIso8601String().replaceAll(':', '-');
    final raw = await _export.invokeMethod<Object>('save', {
      'fileName': 'anki-state-$stamp.json',
      'bytes': bytes,
    });
    if (raw is! Map ||
        !const {
          'verified',
          'written_unverified',
          'cancelled',
        }.contains(raw['status']) ||
        (raw['status'] != 'cancelled' &&
            (raw['uri'] is! String || (raw['uri'] as String).isEmpty))) {
      throw const FormatException('Invalid native export result');
    }
    return Map<String, Object?>.from(raw);
  }

  static Map<String, Object?> _observation(Object? raw, String query) {
    if (raw is! Map ||
        raw['query'] != query ||
        !const {'complete', 'partial', 'unavailable'}.contains(raw['status']) ||
        raw['observed_at_ms'] is! int ||
        (raw['observed_at_ms'] as int) < 0 ||
        raw['cards'] is! List ||
        raw['errors'] is! List) {
      throw const FormatException('Invalid native card-state observation');
    }
    final cards = raw['cards'] as List;
    final total = raw['total'];
    if (raw['status'] == 'unavailable') {
      if (total != null ||
          cards.isNotEmpty ||
          (raw['errors'] as List).isEmpty) {
        throw const FormatException(
          'Unavailable card search has invalid coverage',
        );
      }
    } else if (total is! int || total < cards.length) {
      throw const FormatException('Card search returned inconsistent counts');
    }
    final ids = <int>{};
    for (final card in cards) {
      if (card is! Map ||
          card['card_id'] is! int ||
          (card['card_id'] as int) <= 0 ||
          !ids.add(card['card_id'] as int) ||
          card['note_id'] is! int ||
          (card['note_id'] as int) <= 0 ||
          card['ordinal'] is! int ||
          (card['ordinal'] as int) < 0 ||
          card['state'] is! Map ||
          _stateColumns.any(
            (column) => (card['state'] as Map)[column] is! int,
          ) ||
          (card['source_front_html'] == null &&
              card['source_error'] is! String) ||
          (card['source_front_html'] != null &&
              card['source_front_html'] is! String)) {
        throw const FormatException('Invalid native card identity or fields');
      }
    }
    if (raw['status'] == 'complete' &&
        (total != cards.length ||
            (raw['errors'] as List).isNotEmpty ||
            cards.any((card) => (card as Map).containsKey('source_error')))) {
      throw const FormatException(
        'Incomplete native response claimed complete',
      );
    }
    return Map<String, Object?>.from(raw);
  }
}
