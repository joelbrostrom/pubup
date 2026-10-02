import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:pubup/src/cli.dart';
import 'package:pubup/src/version.dart';
import 'package:test/test.dart';

import '../helpers/fake_sdk.dart';

class _MockPubUpdater extends Mock implements PubUpdater {}

class _MockStdout extends Mock implements Stdout {}

const _quietEnvironment = {'CI': 'true'};

void main() {
  late Directory tempDir;
  late _MockPubUpdater pubUpdater;
  late StringBuffer output;
  late StringBuffer errorOutput;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pubup_cli_');
    pubUpdater = _MockPubUpdater();
    output = StringBuffer();
    errorOutput = StringBuffer();
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<int> run(
    List<String> arguments, {
    http.Client? httpClient,
    Map<String, String> environment = _quietEnvironment,
    bool? isInteractive,
  }) =>
      runCli(
        arguments,
        output: output,
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        httpClient: httpClient,
        environment: environment,
        isInteractive: isInteractive,
      );

  void writeFile(String relativePath, String content) {
    File('${tempDir.path}/$relativePath')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  group('informational commands', () {
    test('--version prints the version', () async {
      expect(await run(['--version']), 0);
      expect(output.toString(), 'pubup $packageVersion\n');
    });

    test('--help prints usage with every option', () async {
      expect(await run(['--help']), 0);

      final help = output.toString();
      expect(help, startsWith('Update pubspec.yaml dependency constraints'));
      for (final option in [
        '--dry-run',
        '--[no-]dev',
        '--package',
        '--root',
        '--bump',
        '--prereleases',
        '--sdk=<path>',
      ]) {
        expect(help, contains(option));
      }
    });

    test('rejects unknown options with usage and exit code 64', () async {
      expect(await run(['--bogus']), 64);

      expect(output.toString(), isEmpty);
      expect(
        errorOutput.toString(),
        startsWith('Error: Could not find an option named "--bogus".\n'),
      );
      expect(errorOutput.toString(), contains('Usage: pubup [options]'));
    });

    test('update --help describes the update command', () async {
      expect(await run(['update', '--help']), 0);

      expect(output.toString(), contains('Reinstall pubup from pub.dev.'));
      verifyNever(() => pubUpdater.getLatestVersion(any()));
    });

    test('writes to stdout and stderr by default', () async {
      final fakeStdout = _MockStdout();
      final fakeStderr = _MockStdout();

      await IOOverrides.runZoned(
        () async {
          expect(await runCli(['--version']), 0);
          expect(await runCli(['--bogus']), 64);
        },
        stdout: () => fakeStdout,
        stderr: () => fakeStderr,
      );

      verify(() => fakeStdout.writeln('pubup $packageVersion')).called(1);
      verify(
        () => fakeStderr.writeln(
          'Error: Could not find an option named "--bogus".',
        ),
      ).called(1);
    });

    test('update reinstalls through pub_updater', () async {
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => packageVersion);

      expect(await run(['update']), 0);

      expect(output.toString(), contains('already at the latest version'));
    });
  });

  group('setup errors', () {
    test('fails when the root has no pubspec.yaml', () async {
      expect(await run(['--root', tempDir.path]), 1);

      expect(
        errorOutput.toString(),
        'Error: Missing root pubspec.yaml '
        '(${tempDir.absolute.path}/pubspec.yaml)\n',
      );
    });

    test('fails when --package matches no workspace member', () async {
      writeFile('pubspec.yaml', 'name: app\n');

      expect(await run(['--root', tempDir.path, '--package', 'nope']), 1);

      expect(
        errorOutput.toString(),
        'No matching workspace packages found for --package filters.\n',
      );
    });

    test('fails when --sdk is not an SDK', () async {
      writeFile('pubspec.yaml', 'name: app\n');

      expect(await run(['--root', tempDir.path, '--sdk', tempDir.path]), 1);

      expect(errorOutput.toString(), contains('(no bin/dart found)'));
    });

    test('prints the update notice after the run', () async {
      when(() => pubUpdater.getLatestVersion(any()))
          .thenAnswer((_) async => '99.0.0');

      await run(
        ['--root', tempDir.path],
        environment: {'PUB_CACHE': '${tempDir.path}/pub_cache'},
        isInteractive: true,
      );

      expect(
        errorOutput.toString(),
        endsWith(
          'pubup 99.0.0 is available (you have $packageVersion). '
          'Run `pubup update` to upgrade.\n',
        ),
      );
    });
  });

  group('updates', () {
    late FakeSdk sdk;

    setUp(() {
      sdk = FakeSdk.create(tempDir)
        ..respond(
          '--version',
          stdout: 'Dart SDK version: 3.10.4 (stable) on "macos_arm64"',
        );
    });

    List<String> args(List<String> extra) => [
          '--root',
          '${tempDir.path}/app',
          '--sdk',
          sdk.root.path,
          ...extra,
        ];

    test('previews a workspace update', () async {
      writeFile('app/pubspec.yaml', '''
name: app
environment:
  sdk: ">=3.0.0 <4.0.0"
workspace:
  - packages/core
dependencies:
  http: ^1.0.0
''');
      writeFile('app/packages/core/pubspec.yaml', '''
name: core
resolution: workspace
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  http: ^1.0.0
''');
      sdk.respond(
        'outdated',
        stdout: outdatedJson([
          outdatedRow('http', current: '1.0.0', resolvable: '1.2.0'),
        ]),
      );

      expect(await run(args(['--dry-run'])), 0);

      expect(
        output.toString(),
        '\n'
        'Workspace: app (dart pub)\n'
        'SDK: Dart 3.10.4 (--sdk ${sdk.root.path})\n'
        '\n'
        '  http  direct  ^1.0.0  ->  ^1.2.0    2 members\n'
        '\n'
        'Summary\n'
        '-------\n'
        '  Updated  2 constraints across 1 dependency\n'
        '  Failed   0\n'
        '\n'
        'Dry-run mode: no files were changed.\n',
      );
      expect(sdk.calls.map((c) => c.arguments), isNot(contains('pub get')));
    });

    test('updates a single package', () async {
      writeFile('app/pubspec.yaml', '''
name: app
dependencies:
  http: ^1.0.0
''');
      sdk.respond(
        'outdated',
        stdout: outdatedJson([
          outdatedRow('http', current: '1.0.0', resolvable: '1.2.0'),
        ]),
      );

      expect(await run(args([])), 0);

      final text = output.toString();
      expect(
        text,
        startsWith(
          '\n'
          'SDK: Dart 3.10.4 (--sdk ${sdk.root.path})\n'
          '\n'
          'Package: . (dart pub)\n'
          '\n'
          '  http  direct  ^1.0.0  ->  ^1.2.0    (was 1.0.0)\n',
        ),
      );
      expect(text, contains('  Updated  1\n'));
      expect(sdk.calls.last.arguments, 'pub add http:^1.2.0');
    });

    test('passes --bump and --prereleases to the updater', () async {
      writeFile('app/pubspec.yaml', '''
name: app
dependencies:
  http: ^1.0.0
  sentry: ^9.0.0
''');
      sdk.respond(
        'outdated',
        stdout: outdatedJson([
          outdatedRow('http', current: '1.0.0', resolvable: '2.0.0'),
          outdatedRow('sentry', current: '9.0.0', resolvable: '9.1.0-rc.1'),
        ]),
      );
      final pubDev = MockClient((request) async {
        expect(request.url.path, '/api/packages/http');
        return http.Response(
          jsonEncode({
            'versions': [
              {'version': '1.0.0'},
              {'version': '1.5.0'},
              {'version': '2.0.0'},
            ],
          }),
          200,
        );
      });

      await run(
        args(['--dry-run', '--bump', 'minor', '--prereleases']),
        httpClient: pubDev,
      );

      final text = output.toString();
      expect(text, contains('  http    direct  ^1.0.0  ->  ^1.5.0'));
      expect(text, contains('  sentry  direct  ^9.0.0  ->  ^9.1.0-rc.1'));
    });

    test('reports a failed package scan and exits with 1', () async {
      writeFile('app/pubspec.yaml', 'name: app\n');
      sdk.respond('outdated', stderr: 'pubspec.lock is missing', exitCode: 66);

      expect(await run(args([])), 1);

      expect(
        errorOutput.toString(),
        contains(
          '  ! Failed package scan: ProcessException: '
          'pubspec.lock is missing',
        ),
      );
      expect(output.toString(), contains('Failures (1)'));
      expect(output.toString(), contains('  Failed   1\n'));
    });
  }, skip: fakeSdkSkip);
}
