import 'dart:io';

import 'package:pubup/src/workspace_mode.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pubup_ws_mode_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('isWorkspaceRoot', () {
    test('returns false when pubspec is missing', () {
      final missing = File('${tempDir.path}/pubspec.yaml');
      expect(isWorkspaceRoot(missing), isFalse);
    });

    test('returns false when workspace section is absent', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: my_app
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
      expect(isWorkspaceRoot(File('${tempDir.path}/pubspec.yaml')), isFalse);
    });

    test('returns false when workspace list is empty', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: my_app
workspace:
''');
      expect(isWorkspaceRoot(File('${tempDir.path}/pubspec.yaml')), isFalse);
    });

    test('returns false when workspace is not a list', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: my_app
workspace: packages/foo
''');
      expect(isWorkspaceRoot(File('${tempDir.path}/pubspec.yaml')), isFalse);
    });

    test('returns true when workspace has entries', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: my_app
workspace:
  - packages/pkg_a
''');
      expect(isWorkspaceRoot(File('${tempDir.path}/pubspec.yaml')), isTrue);
    });
  });

  group('isWorkspaceRootFromString', () {
    test('returns false for malformed YAML', () {
      expect(isWorkspaceRootFromString('not: [yaml'), isFalse);
    });

    test('returns true for non-empty workspace list', () {
      const content = '''
name: my_app
workspace:
  - packages/a
  - packages/b
''';
      expect(isWorkspaceRootFromString(content), isTrue);
    });

    test('returns false when workspace entries are not strings', () {
      const content = '''
name: my_app
workspace:
  - 1
''';
      expect(isWorkspaceRootFromString(content), isFalse);
    });
  });
}
