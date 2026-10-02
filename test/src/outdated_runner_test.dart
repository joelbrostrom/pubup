import 'dart:io';

import 'package:pubup/src/outdated_runner.dart';
import 'package:test/test.dart';

import '../helpers/fake_sdk.dart';

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
      expect(result.first.latestVersion, isNull);
    });

    test('parses the latest version when present', () {
      const stdout = '{"packages":['
          '{"package":"equatable","kind":"direct",'
          '"current":{"version":"2.1.0"},'
          '"resolvable":{"version":"2.1.0"},'
          '"latest":{"version":"3.0.0"}}'
          ']}';

      final result = parseOutdatedJson(stdout);

      expect(result.single.latestVersion, '3.0.0');
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
      expect(() => parseOutdatedJson(''), throwsA(isA<FormatException>()));
    });
  });

  group('getOutdatedPackages', () {
    late Directory tempDir;
    late FakeSdk sdk;
    late Directory packageDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pubup_outdated_');
      sdk = FakeSdk.create(tempDir);
      packageDir = Directory('${tempDir.path}/my_package')..createSync();
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    test('runs pub outdated in the package directory', () async {
      sdk.respond(
        'outdated',
        stdout: outdatedJson([
          outdatedRow('http', current: '1.0.0', resolvable: '1.2.0'),
        ]),
      );

      final packages = await getOutdatedPackages(
        sdk.pubSdk.executable('flutter'),
        packageDir,
      );

      expect(packages.single.package, 'http');
      expect(packages.single.resolvableVersion, '1.2.0');
      final call = sdk.calls.single;
      expect(call.executable, 'flutter');
      expect(call.workingDirectory, packageDir.resolveSymbolicLinksSync());
      expect(call.arguments, 'pub outdated --json --show-all');
    });

    test('throws a ProcessException with stderr when pub fails', () async {
      sdk.respond(
        'outdated',
        stdout: 'Resolving dependencies...',
        stderr: 'Could not find package foo\n',
        exitCode: 65,
      );
      final executable = sdk.pubSdk.executable('dart');

      await expectLater(
        getOutdatedPackages(executable, packageDir),
        throwsA(
          isA<ProcessException>()
              .having((e) => e.executable, 'executable', executable)
              .having((e) => e.message, 'message', 'Could not find package foo')
              .having((e) => e.errorCode, 'errorCode', 65),
        ),
      );
    });

    test('falls back to stdout when pub fails without stderr', () async {
      sdk.respond('outdated', stdout: 'No pubspec.yaml found.\n', exitCode: 1);

      await expectLater(
        getOutdatedPackages(sdk.pubSdk.executable('dart'), packageDir),
        throwsA(
          isA<ProcessException>().having(
            (e) => e.message,
            'message',
            'No pubspec.yaml found.',
          ),
        ),
      );
    });
  }, skip: fakeSdkSkip);
}
