import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:people_tracker/core/integrations_config_service.dart';

void main() {
  test('current integration config owns only live Anki settings', () async {
    final vault = await Directory.systemTemp.createTemp('interest_config_');
    addTearDown(() => vault.delete(recursive: true));

    final saved = await IntegrationsConfigService.save(
      vault.path,
      const IntegrationsConfig(
        ankiConnectUrl: 'http://127.0.0.1:8765',
        excludedFolders: ['Archive'],
      ),
    );

    expect(saved, isTrue);
    final text =
        await File(
          IntegrationsConfigService.configPath(vault.path),
        ).readAsString();
    expect(text, contains('## AnkiConnect'));
    expect(text, contains('## Resurface'));
    expect(text, isNot(contains('Hardcover')));

    final loaded = await IntegrationsConfigService.load(vault.path);
    expect(loaded.ankiConnectUrl, 'http://127.0.0.1:8765');
    expect(loaded.excludedFolders, ['Archive']);
  });

  test('config write failure is an explicit non-success', () async {
    final temp = await Directory.systemTemp.createTemp('interest_config_fail_');
    addTearDown(() => temp.delete(recursive: true));
    final notAVault = File('${temp.path}${Platform.pathSeparator}not-a-vault')
      ..writeAsStringSync('occupied');

    final saved = await IntegrationsConfigService.save(
      notAVault.path,
      const IntegrationsConfig(excludedFolders: ['Archive']),
    );

    expect(saved, isFalse);
  });
}
