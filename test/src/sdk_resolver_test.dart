import 'dart:io';

import 'package:pubup/src/sdk_resolver.dart';
import 'package:test/test.dart';

const _flutterMachineJson = '''
{
  "frameworkVersion": "3.38.5",
  "channel": "stable",
  "dartSdkVersion": "3.10.4",
  "flutterVersion": "3.38.5",
  "flutterRoot": "/Users/me/fvm/versions/3.38.5"
}
''';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pubup_sdk_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  void writeFile(String relativePath, [String content = '']) {
    final file = File('${tempDir.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  group('resolvePubSdk', () {
    test('uses PATH when the project has no FVM files', () {
      final sdk = resolvePubSdk(repoRoot: tempDir);

      expect(sdk.root, isNull);
      expect(sdk.origin, 'PATH');
    });

    test('uses the version pinned in .fvmrc', () {
      writeFile('.fvmrc', '{"flutter": "3.38.5"}');
      writeFile('.fvm/versions/3.38.5/bin/flutter');
      writeFile('.fvm/flutter_sdk/bin/flutter');

      final sdk = resolvePubSdk(repoRoot: tempDir);

      expect(sdk.root, '${tempDir.path}/.fvm/versions/3.38.5');
      expect(sdk.origin, 'FVM .fvm/versions/3.38.5');
    });

    test('warns and uses PATH when the pinned version is not linked', () {
      writeFile('.fvmrc', '{"flutter": "3.38.5"}');
      writeFile('.fvm/flutter_sdk/bin/flutter');
      final warnings = StringBuffer();

      final sdk = resolvePubSdk(repoRoot: tempDir, warnings: warnings);

      expect(sdk.root, isNull);
      expect(warnings.toString(), contains('.fvmrc pins Flutter 3.38.5'));
      expect(warnings.toString(), contains('fvm use 3.38.5'));
    });

    test('falls back to .fvm/flutter_sdk without a usable .fvmrc', () {
      writeFile('.fvmrc', 'not json');
      writeFile('.fvm/flutter_sdk/bin/flutter');
      final warnings = StringBuffer();

      final sdk = resolvePubSdk(repoRoot: tempDir, warnings: warnings);

      expect(sdk.root, '${tempDir.path}/.fvm/flutter_sdk');
      expect(sdk.origin, 'FVM .fvm/flutter_sdk');
      expect(warnings.toString(), isEmpty);
    });

    test('ignores an .fvmrc without a flutter version', () {
      writeFile('.fvmrc', '{"flavors": {}}');

      final sdk = resolvePubSdk(repoRoot: tempDir);

      expect(sdk.root, isNull);
    });

    test('--sdk wins over the FVM pin', () {
      writeFile('.fvmrc', '{"flutter": "3.38.5"}');
      writeFile('.fvm/versions/3.38.5/bin/flutter');
      writeFile('custom/bin/dart');

      final sdk = resolvePubSdk(
        repoRoot: tempDir,
        sdkPath: '${tempDir.path}/custom',
      );

      expect(sdk.root, '${tempDir.path}/custom');
      expect(sdk.origin, '--sdk ${tempDir.path}/custom');
    });

    test('throws when --sdk has no bin/dart', () {
      expect(
        () => resolvePubSdk(repoRoot: tempDir, sdkPath: tempDir.path),
        throwsA(
          isA<SdkResolutionException>().having(
            (e) => e.toString(),
            'toString()',
            contains('no bin/dart found'),
          ),
        ),
      );
    });
  });

  group('PubSdk.executable', () {
    test('returns the bare command for PATH', () {
      expect(const PubSdk.fromPath().executable('flutter'), 'flutter');
    });

    test('returns the SDK bin path', () {
      const sdk = PubSdk.at('/sdks/flutter', origin: 'test');
      expect(
        sdk.executable('dart', isWindows: false),
        '/sdks/flutter/bin/dart',
      );
    });

    test('prefers the .exe on Windows', () {
      writeFile('bin/dart.exe');
      final sdk = PubSdk.at(tempDir.path, origin: 'test');

      expect(
        sdk.executable('dart', isWindows: true),
        '${tempDir.path}/bin/dart.exe',
      );
    });

    test('falls back to the .bat on Windows', () {
      writeFile('bin/flutter.bat');
      final sdk = PubSdk.at(tempDir.path, origin: 'test');

      expect(
        sdk.executable('flutter', isWindows: true),
        '${tempDir.path}/bin/flutter.bat',
      );
    });
  });

  group('describeSdk', () {
    test('describes a Flutter SDK picked from FVM', () async {
      const sdk = PubSdk.at('/repo/.fvm/versions/3.38.5', origin: 'FVM x');
      final calls = <List<String>>[];

      final line = await describeSdk(
        sdk: sdk,
        command: 'flutter',
        run: (executable, args) async {
          calls.add([executable, ...args]);
          return ProcessResult(0, 0, _flutterMachineJson, '');
        },
      );

      expect(line, 'SDK: Flutter 3.38.5, Dart 3.10.4 (FVM x)');
      expect(calls.single, [
        sdk.executable('flutter'),
        '--version',
        '--machine',
      ]);
    });

    test('shows the Flutter root when using PATH', () async {
      final line = await describeSdk(
        sdk: const PubSdk.fromPath(),
        command: 'flutter',
        run: (_, __) async => ProcessResult(0, 0, _flutterMachineJson, ''),
      );

      expect(
        line,
        'SDK: Flutter 3.38.5, Dart 3.10.4 '
        '(PATH: /Users/me/fvm/versions/3.38.5)',
      );
    });

    test('describes a Dart SDK', () async {
      final line = await describeSdk(
        sdk: const PubSdk.fromPath(),
        command: 'dart',
        run: (_, __) async => ProcessResult(
          0,
          0,
          'Dart SDK version: 3.10.4 (stable) on "macos_arm64"',
          '',
        ),
      );

      expect(line, 'SDK: Dart 3.10.4 (PATH)');
    });

    test('reports an unknown version when the command fails', () async {
      final line = await describeSdk(
        sdk: const PubSdk.fromPath(),
        command: 'flutter',
        run: (_, __) async => ProcessResult(0, 1, '', 'boom'),
      );

      expect(line, 'SDK: unknown version (PATH)');
    });

    test('runs the real dart --version by default', () async {
      final dartSdk = File(Platform.resolvedExecutable).parent.parent.path;
      final runningVersion = Platform.version.split(' ').first;

      final line = await describeSdk(
        sdk: PubSdk.at(dartSdk, origin: 'test'),
        command: 'dart',
      );

      expect(line, 'SDK: Dart $runningVersion (test)');
    });

    test('reports an unknown version when the executable is missing', () async {
      final line = await describeSdk(
        sdk: const PubSdk.fromPath(),
        command: 'dart',
        run: (executable, args) async =>
            throw ProcessException(executable, args, 'not found', 2),
      );

      expect(line, 'SDK: unknown version (PATH)');
    });
  });

  group('parseFlutterVersionOutput', () {
    test('tolerates banners around the JSON', () {
      final version = parseFlutterVersionOutput(
        'A new version of Flutter is available!\n$_flutterMachineJson\n',
      );

      expect(version?.flutter, '3.38.5');
      expect(version?.dart, '3.10.4');
      expect(version?.flutterRoot, '/Users/me/fvm/versions/3.38.5');
    });

    test('keeps only the version from pre-release Dart builds', () {
      final version = parseFlutterVersionOutput(
        '{"frameworkVersion": "3.39.0-0.1.pre", '
        '"dartSdkVersion": "3.11.0 (build 3.11.0-100.0.dev)"}',
      );

      expect(version?.describe(), 'Flutter 3.39.0-0.1.pre, Dart 3.11.0');
    });

    test('returns null without a Flutter version', () {
      expect(parseFlutterVersionOutput('{"dartSdkVersion": "3.10.4"}'), isNull);
      expect(parseFlutterVersionOutput('{not json}'), isNull);
      expect(parseFlutterVersionOutput('[]'), isNull);
      expect(parseFlutterVersionOutput('no json'), isNull);
    });
  });

  group('parseDartVersionOutput', () {
    test('reads the version', () {
      expect(
        parseDartVersionOutput('Dart SDK version: 3.10.4 (stable)')?.dart,
        '3.10.4',
      );
    });

    test('returns null for unrelated output', () {
      expect(parseDartVersionOutput('command not found'), isNull);
    });
  });
}
