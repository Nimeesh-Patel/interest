import 'package:path/path.dart' as p;

/// Pure filesystem layout shared by Flutter UI code and standalone Dart tools.
class VaultPaths {
  VaultPaths._();

  static String templates(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Templates');

  static String system(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'System');

  static String projects(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Projects');

  static String inbox(String vaultPath) =>
      p.join(vaultPath, 'Interesting', 'Inbox.md');
}
