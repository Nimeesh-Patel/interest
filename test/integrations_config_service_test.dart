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
  test(
    'invalid authored settings are errors rather than missing exclusions',
    () async {
      final vault = await Directory.systemTemp.createTemp('invalid_config_');
      addTearDown(() => vault.delete(recursive: true));
      final file = File(IntegrationsConfigService.configPath(vault.path));
      await file.parent.create(recursive: true);
      for (final source in [
        '## Resurface\nexcluded_folders: [Archive',
        '## Resurface\nexcluded_folders: 42',
        '## AnkiConnect\nurl: [wrong]',
        '## Resurface\nexcluded_folders: [Archive]\n## Resurface\nexcluded_folders: []',
      ]) {
        await file.writeAsString(source);
        expect(
          IntegrationsConfigService.load(vault.path),
          throwsFormatException,
        );
        expect(
          await IntegrationsConfigService.setExcludedFolders(vault.path, [
            'Other',
          ]),
          isFalse,
        );
        expect(await file.readAsString(), source);
      }
    },
  );

  test(
    'exclusion changes preserve endpoint, unknown fields and unrelated sections',
    () async {
      final vault = await Directory.systemTemp.createTemp('preserved_config_');
      addTearDown(() => vault.delete(recursive: true));
      final file = File(IntegrationsConfigService.configPath(vault.path));
      await file.parent.create(recursive: true);
      const source =
          '---\ncustom: exact\n---\n\n## AnkiConnect\nurl: http://127.0.0.1:9999\nunknown: kept\n\n## Resurface\n# Keep comment\nexcluded_folders: [Archive]\nother: kept\n\n## My research\nSome independent text.\n';
      await file.writeAsString(source);
      expect(
        await IntegrationsConfigService.setExcludedFolders(vault.path, [
          'Other',
        ]),
        isTrue,
      );
      final observed = await file.readAsString();
      expect(observed, source.replaceFirst('[Archive]', '[Other]'));
      expect(
        (await IntegrationsConfigService.load(vault.path)).ankiConnectUrl,
        'http://127.0.0.1:9999',
      );
    },
  );
}
