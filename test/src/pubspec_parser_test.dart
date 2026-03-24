import 'package:pubup/src/pubspec_parser.dart';
import 'package:test/test.dart';

void main() {
  group('parseDependencyEntriesFromString', () {
    test('parses scalar hosted dependencies', () {
      const yaml = '''
dependencies:
  http: ^1.2.0
  path: ^1.9.0
''';
      final result = parseDependencyEntriesFromString(yaml);
      expect(result.direct, hasLength(2));
      expect(result.direct['http']!.source, 'hosted');
      expect(result.direct['http']!.constraint, '^1.2.0');
      expect(result.direct['path']!.source, 'hosted');
      expect(result.direct['path']!.constraint, '^1.9.0');
    });

    test('parses dev_dependencies', () {
      const yaml = '''
dev_dependencies:
  test: ^1.24.0
  lints: ^4.0.0
''';
      final result = parseDependencyEntriesFromString(yaml);
      expect(result.dev, hasLength(2));
      expect(result.dev['test']!.source, 'hosted');
      expect(result.dev['test']!.constraint, '^1.24.0');
    });

    test('identifies path dependencies', () {
      const yaml = '''
dependencies:
  my_package:
    path: ../my_package
''';
      final result = parseDependencyEntriesFromString(yaml);
      expect(result.direct['my_package']!.source, 'path');
      expect(result.direct['my_package']!.constraint, isNull);
    });

    test('identifies git dependencies', () {
      const yaml = '''
dependencies:
  my_package:
    git:
      url: https://github.com/user/repo.git
      ref: main
''';
      final result = parseDependencyEntriesFromString(yaml);
      expect(result.direct['my_package']!.source, 'git');
    });

    test('identifies sdk dependencies', () {
      const yaml = '''
dependencies:
  flutter:
    sdk: flutter
''';
      final result = parseDependencyEntriesFromString(yaml);
      expect(result.direct['flutter']!.source, 'sdk');
      expect(result.direct['flutter']!.constraint, 'flutter');
    });

    test('handles hosted block form with version', () {
      const yaml = '''
dependencies:
  my_package:
    hosted: https://custom-pub.example.com
    version: ^2.0.0
''';
      final result = parseDependencyEntriesFromString(yaml);
      expect(result.direct['my_package']!.source, 'hosted');
      expect(result.direct['my_package']!.constraint, '^2.0.0');
    });

    test('handles null value as any', () {
      const yaml = '''
dependencies:
  my_package:
''';
      final result = parseDependencyEntriesFromString(yaml);
      expect(result.direct['my_package']!.source, 'hosted');
      expect(result.direct['my_package']!.constraint, 'any');
    });

    test('handles "any" string value', () {
      const yaml = '''
dependencies:
  my_package: any
''';
      final result = parseDependencyEntriesFromString(yaml);
      expect(result.direct['my_package']!.source, 'hosted');
      expect(result.direct['my_package']!.constraint, 'any');
    });

    test('handles empty pubspec', () {
      const yaml = 'name: empty_package';
      final result = parseDependencyEntriesFromString(yaml);
      expect(result.direct, isEmpty);
      expect(result.dev, isEmpty);
    });

    test('handles mixed dependency types', () {
      const yaml = '''
dependencies:
  http: ^1.2.0
  flutter:
    sdk: flutter
  local_pkg:
    path: ../local_pkg
  git_pkg:
    git:
      url: https://github.com/user/repo.git
  hosted_pkg:
    hosted: https://custom.example.com
    version: ^3.0.0

dev_dependencies:
  test: ^1.24.0
  build_runner: ^2.4.0
''';
      final result = parseDependencyEntriesFromString(yaml);
      expect(result.direct['http']!.source, 'hosted');
      expect(result.direct['flutter']!.source, 'sdk');
      expect(result.direct['local_pkg']!.source, 'path');
      expect(result.direct['git_pkg']!.source, 'git');
      expect(result.direct['hosted_pkg']!.source, 'hosted');
      expect(result.direct['hosted_pkg']!.constraint, '^3.0.0');
      expect(result.dev['test']!.source, 'hosted');
      expect(result.dev['build_runner']!.source, 'hosted');
    });

    test('handles version with build metadata', () {
      const yaml = '''
dependencies:
  provider: ^6.1.5+1
''';
      final result = parseDependencyEntriesFromString(yaml);
      expect(result.direct['provider']!.constraint, '^6.1.5+1');
    });
  });

  group('isFlutterPackageFromString', () {
    test('returns true for Flutter packages', () {
      const yaml = '''
dependencies:
  flutter:
    sdk: flutter
  http: ^1.0.0
''';
      expect(isFlutterPackageFromString(yaml), isTrue);
    });

    test('returns false for pure Dart packages', () {
      const yaml = '''
dependencies:
  http: ^1.0.0
  yaml: ^3.1.0
''';
      expect(isFlutterPackageFromString(yaml), isFalse);
    });

    test('returns false for empty pubspec', () {
      expect(isFlutterPackageFromString('name: test'), isFalse);
    });
  });
}
