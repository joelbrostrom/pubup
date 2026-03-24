import 'dart:io';

import 'package:pubup/src/workspace_discovery.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pubup_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  void writeFile(String relativePath, String content) {
    final file = File('${tempDir.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  group('discoverWorkspaceDirs', () {
    test('returns only root when no workspace section', () {
      writeFile('pubspec.yaml', '''
name: my_app
environment:
  sdk: ">=3.0.0 <4.0.0"
''');

      final dirs = discoverWorkspaceDirs(tempDir);
      expect(dirs, hasLength(1));
      expect(dirs.first.path, tempDir.path);
    });

    test('discovers workspace packages', () {
      writeFile('pubspec.yaml', '''
name: my_app
workspace:
  - packages/pkg_a
  - packages/pkg_b
''');
      writeFile('packages/pkg_a/pubspec.yaml', 'name: pkg_a');
      writeFile('packages/pkg_b/pubspec.yaml', 'name: pkg_b');

      final dirs = discoverWorkspaceDirs(tempDir);
      expect(dirs, hasLength(3));
      expect(dirs[0].path, tempDir.path);
      expect(dirs[1].path, contains('pkg_a'));
      expect(dirs[2].path, contains('pkg_b'));
    });

    test('skips workspace entries without pubspec.yaml', () {
      writeFile('pubspec.yaml', '''
name: my_app
workspace:
  - packages/exists
  - packages/missing
''');
      writeFile('packages/exists/pubspec.yaml', 'name: exists');

      final dirs = discoverWorkspaceDirs(tempDir);
      expect(dirs, hasLength(2));
    });

    test('throws when root pubspec.yaml is missing', () {
      expect(
        () => discoverWorkspaceDirs(tempDir),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('handles empty workspace list', () {
      writeFile('pubspec.yaml', '''
name: my_app
workspace:
''');

      final dirs = discoverWorkspaceDirs(tempDir);
      expect(dirs, hasLength(1));
    });
  });

  group('filterTargets', () {
    test('returns all targets when selectors is empty', () {
      final targets = [tempDir];
      final result = filterTargets(targets, [], tempDir);
      expect(result, hasLength(1));
    });

    test('filters by directory name', () {
      writeFile('pubspec.yaml', 'name: root');
      writeFile('packages/pkg_a/pubspec.yaml', 'name: pkg_a');

      final pkgA = Directory('${tempDir.path}/packages/pkg_a');
      final targets = [tempDir, pkgA];

      final result = filterTargets(targets, ['pkg_a'], tempDir);
      expect(result, hasLength(1));
      expect(result.first.path, pkgA.path);
    });

    test('filters root by "." selector', () {
      final targets = [tempDir];
      final result = filterTargets(targets, ['.'], tempDir);
      expect(result, hasLength(1));
    });

    test('filters root by "root" selector', () {
      final targets = [tempDir];
      final result = filterTargets(targets, ['root'], tempDir);
      expect(result, hasLength(1));
    });

    test('returns empty when no match', () {
      final targets = [tempDir];
      final result = filterTargets(targets, ['nonexistent'], tempDir);
      expect(result, isEmpty);
    });

    test('filters by relative path', () {
      writeFile('packages/pkg_a/pubspec.yaml', 'name: pkg_a');
      final pkgA = Directory('${tempDir.path}/packages/pkg_a');
      final targets = [tempDir, pkgA];

      final result = filterTargets(targets, ['packages/pkg_a'], tempDir);
      expect(result, hasLength(1));
      expect(result.first.path, pkgA.path);
    });
  });
}
