import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:people_tracker/features/anki/services/card_criticisms.dart';
import 'package:yaml/yaml.dart';

/// Perspirator reads `criticisms:` without a YAML library. Both readers are
/// held to the same cases; the canonical copy lives in Perspirator 9000's
/// `fixtures/`, and its doctor reports this copy if it drifts.
void main() {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/criticisms_conformance.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  for (final raw in fixture['cases'] as List<dynamic>) {
    final item = raw as Map<String, dynamic>;
    test(item['name'], () {
      final map = loadYaml(item['frontmatter'] as String) as YamlMap?;
      List<String> read() =>
          CardCriticisms.targets(
            CardCriticisms.parse(map?[CardCriticisms.property]),
          ).toList();
      if (item['error'] == true) {
        expect(read, throwsFormatException);
      } else {
        expect(read(), (item['targets'] as List<dynamic>).cast<String>());
      }
    });
  }
}
