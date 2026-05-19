import 'package:pubup/src/outdated_runner.dart';
import 'package:test/test.dart';

void main() {
  group('parseOutdatedJson', () {
    test('parses a clean JSON object', () {
      const stdout = '{"packages":['
          '{"package":"http","kind":"direct",'
          '"current":{"version":"1.2.0"},'
          '"resolvable":{"version":"1.3.0"}}'
          ']}';

      final result = parseOutdatedJson(stdout);

      expect(result, hasLength(1));
      expect(result.first.package, 'http');
      expect(result.first.kind, 'direct');
      expect(result.first.currentVersion, '1.2.0');
      expect(result.first.resolvableVersion, '1.3.0');
    });

    test('ignores Flutter version banner printed after JSON', () {
      // Reproduces the real-world failure where `flutter pub outdated --json`
      // appends the "A new version of Flutter is available" banner to stdout
      // after the JSON payload.
      const stdout = '{"packages":['
          '{"package":"equatable","kind":"direct",'
          '"current":{"version":"2.0.7"},'
          '"resolvable":{"version":"2.0.8"}}'
          ']}\n'
          '┌─────────────────────────────────────────────────────────┐\n'
          '│ A new version of Flutter is available!                  │\n'
          '└─────────────────────────────────────────────────────────┘\n';

      final result = parseOutdatedJson(stdout);

      expect(result, hasLength(1));
      expect(result.first.package, 'equatable');
      expect(result.first.resolvableVersion, '2.0.8');
    });

    test('ignores noise printed before JSON', () {
      const stdout = 'Resolving dependencies...\n'
          'Got dependencies!\n'
          '{"packages":[]}';

      final result = parseOutdatedJson(stdout);

      expect(result, isEmpty);
    });

    test('skips rows with non-direct/dev kinds and missing fields', () {
      const stdout = '{"packages":['
          '{"package":"a","kind":"direct",'
          '"current":{"version":"1.0.0"},'
          '"resolvable":{"version":"1.1.0"}},'
          '{"package":"b","kind":"transitive",'
          '"current":{"version":"2.0.0"},'
          '"resolvable":{"version":"2.0.0"}},'
          '{"package":"c","kind":"direct"}'
          ']}';

      final result = parseOutdatedJson(stdout);

      // "c" is dropped because required fields are missing; "b" is kept here
      // (transitive filtering happens in the candidate collector).
      expect(result.map((r) => r.package), ['a', 'b']);
    });

    test('throws FormatException when no JSON object is present', () {
      expect(
        () => parseOutdatedJson('no json here'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException on empty stdout', () {
      expect(
        () => parseOutdatedJson(''),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
