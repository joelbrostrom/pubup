import 'package:pubup/src/constraint_rewriter.dart';
import 'package:test/test.dart';

void main() {
  group('rewriteConstraint', () {
    test('replaces caret constraint preserving indentation', () {
      const content = '''
name: app
dependencies:
  http: ^1.0.0
  path: any
''';
      final result = rewriteConstraint(
        content: content,
        section: 'dependencies',
        packageName: 'http',
        newConstraint: '^1.2.0',
      );

      expect(result.changed, isTrue);
      expect(result.content, contains('  http: ^1.2.0'));
      expect(result.content, contains('  path: any'));
    });

    test('preserves trailing comment', () {
      const content = '''
dependencies:
  http: ^1.0.0 # networking
''';
      final result = rewriteConstraint(
        content: content,
        section: 'dependencies',
        packageName: 'http',
        newConstraint: '^1.2.0',
      );

      expect(result.changed, isTrue);
      expect(result.content, contains('  http: ^1.2.0 # networking'));
    });

    test('leaves any constraint untouched', () {
      const content = '''
dependencies:
  foo: any
''';
      final result = rewriteConstraint(
        content: content,
        section: 'dependencies',
        packageName: 'foo',
        newConstraint: '^2.0.0',
      );

      expect(result.changed, isFalse);
      expect(result.content, content);
    });

    test('leaves range constraints untouched', () {
      const content = '''
dependencies:
  foo: ">=1.0.0 <2.0.0"
''';
      final result = rewriteConstraint(
        content: content,
        section: 'dependencies',
        packageName: 'foo',
        newConstraint: '^2.0.0',
      );

      expect(result.changed, isFalse);
    });

    test('does not touch dependency_overrides', () {
      const content = '''
dependencies:
  http: ^1.0.0
dependency_overrides:
  http: ^9.0.0
''';
      final result = rewriteConstraint(
        content: content,
        section: 'dependencies',
        packageName: 'http',
        newConstraint: '^1.2.0',
      );

      expect(result.changed, isTrue);
      expect(result.content, contains('dependencies:\n  http: ^1.2.0'));
      expect(result.content, contains('dependency_overrides:\n  http: ^9.0.0'));
    });

    test('distinguishes dependencies vs dev_dependencies', () {
      const content = '''
dependencies:
  http: ^1.0.0
dev_dependencies:
  test: ^1.0.0
''';
      final result = rewriteConstraint(
        content: content,
        section: 'dev_dependencies',
        packageName: 'test',
        newConstraint: '^2.0.0',
      );

      expect(result.changed, isTrue);
      expect(result.content, contains('  http: ^1.0.0'));
      expect(result.content, contains('  test: ^2.0.0'));
    });

    test('no-op when package is not in target section', () {
      const content = '''
dependencies:
  http: ^1.0.0
''';
      final result = rewriteConstraint(
        content: content,
        section: 'dev_dependencies',
        packageName: 'http',
        newConstraint: '^2.0.0',
      );

      expect(result.changed, isFalse);
    });

    test('rewrites version subkey under package block', () {
      const content = '''
dependencies:
  hosted_pkg:
    version: ^1.0.0
''';
      final result = rewriteConstraint(
        content: content,
        section: 'dependencies',
        packageName: 'hosted_pkg',
        newConstraint: '^2.0.0',
      );

      expect(result.changed, isTrue);
      expect(result.content, contains('    version: ^2.0.0'));
    });

    test('returns unchanged for invalid section name', () {
      const content = 'dependencies:\n  http: ^1.0.0\n';
      final result = rewriteConstraint(
        content: content,
        section: 'dependency_overrides',
        packageName: 'http',
        newConstraint: '^2.0.0',
      );

      expect(result.changed, isFalse);
      expect(result.content, content);
    });
  });
}
