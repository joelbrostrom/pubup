import 'dart:io';

import 'package:pubup/src/reporter.dart';
import 'package:pubup/src/updater.dart';
import 'package:test/test.dart';

import '../helpers/fake_sdk.dart';

const _pubspec = '''
name: my_app
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  http: ^1.0.0
  path: ^1.9.0
  broken: ^2.0.0
dev_dependencies:
  lints: ^5.0.0
''';

void main() {
  group('runUpdatesForPackage', () {
    late Directory tempDir;
    late Directory packageDir;
    late FakeSdk sdk;
    late StringBuffer output;
    late StringBuffer errorOutput;
    late List<String?> statuses;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pubup_updater_');
      packageDir = Directory('${tempDir.path}/my_app')..createSync();
      File('${packageDir.path}/pubspec.yaml').writeAsStringSync(_pubspec);
      sdk = FakeSdk.create(tempDir);
      output = StringBuffer();
      errorOutput = StringBuffer();
      statuses = [];
    });

    tearDown(() => tempDir.deleteSync(recursive: true));

    void outdated(List<Map<String, Object?>> rows) =>
        sdk.respond('outdated', stdout: outdatedJson(rows));

    Future<PackageReport> run({bool dryRun = false}) => runUpdatesForPackage(
          packageDir: packageDir,
          command: 'dart',
          includeDev: true,
          dryRun: dryRun,
          output: output,
          errorOutput: errorOutput,
          executable: sdk.pubSdk.executable('dart'),
          onStatus: statuses.add,
        );

    List<String> pubCalls() => [for (final c in sdk.calls) c.arguments];

    test('previews every candidate without running pub add', () async {
      outdated([
        outdatedRow('http', current: '1.0.0', resolvable: '1.2.0'),
        outdatedRow('path', current: '1.9.1', resolvable: '1.9.1'),
        outdatedRow(
          'lints',
          kind: 'dev',
          current: '5.0.0',
          resolvable: '6.0.0',
        ),
      ]);

      final report = await run(dryRun: true);

      expect(pubCalls(), ['pub outdated --json --show-all']);
      expect(
        sdk.calls.single.workingDirectory,
        packageDir.resolveSymbolicLinksSync(),
      );
      expect(report.attempted, 3);
      expect(report.changed, 3);
      final lines = output.toString().trimRight().split('\n');
      expect(lines, [
        '  http   direct  ^1.0.0  ->  ^1.2.0    (was 1.0.0)',
        '  path   direct  ^1.9.0  ->  ^1.9.1',
        '  lints  dev     ^5.0.0  ->  ^6.0.0    (was 5.0.0)',
      ]);
    });

    test('applies every update with a single pub add', () async {
      outdated([
        outdatedRow('http', current: '1.0.0', resolvable: '1.2.0'),
        outdatedRow(
          'lints',
          kind: 'dev',
          current: '5.0.0',
          resolvable: '6.0.0',
        ),
      ]);

      final report = await run();

      expect(pubCalls(), [
        'pub outdated --json --show-all',
        'pub add http:^1.2.0 dev:lints:^6.0.0',
      ]);
      expect(report.changed, 2);
      expect(report.failed, 0);
      expect(errorOutput.toString(), isEmpty);
      expect(statuses, [
        'Scanning for outdated dependencies',
        null,
        'Running dart pub add',
        null,
      ]);
    });

    test(
      'retries one by one after a failed batch and reports failures',
      () async {
        outdated([
          outdatedRow('http', current: '1.0.0', resolvable: '1.2.0'),
          outdatedRow('broken', current: '2.0.0', resolvable: '2.1.0'),
        ]);
        sdk.failWhenArgumentContains(
          'add',
          'broken',
          stderr: 'Because my_app depends on broken ^2.1.0, '
              'version solving failed.\n',
        );

        final report = await run();

        expect(pubCalls(), [
          'pub outdated --json --show-all',
          'pub add http:^1.2.0 broken:^2.1.0',
          'pub add http:^1.2.0',
          'pub add broken:^2.1.0',
        ]);
        expect(report.changed, 1);
        expect(report.failed, 1);
        expect(report.failures, [
          'broken: Because my_app depends on broken ^2.1.0, '
              'version solving failed.',
        ]);
        expect(
          errorOutput.toString(),
          contains('Batched update failed; retrying 2 updates individually'),
        );
        expect(statuses.skip(4), [
          'Retrying http (1/2)',
          'Retrying broken (2/2)',
          null,
        ]);
      },
    );

    test('reports pub add stdout when stderr is empty', () async {
      outdated([outdatedRow('broken', current: '2.0.0', resolvable: '2.1.0')]);
      sdk.failWhenArgumentContains(
        'add',
        'broken',
        stdout: 'version solving failed.\n',
      );

      final report = await run();

      expect(report.failures, ['broken: version solving failed.']);
    });

    test('runs nothing else when no dependency needs an update', () async {
      outdated([
        outdatedRow(
          'http',
          current: '1.0.0',
          resolvable: '1.0.0',
          latest: '2.0.0',
        ),
        outdatedRow('path', current: '1.9.0', resolvable: '2.0.0-rc.1'),
        outdatedRow(
          'lints',
          kind: 'dev',
          current: '5.0.0',
          resolvable: '6.0.0',
        ),
      ]);

      final report = await runUpdatesForPackage(
        packageDir: packageDir,
        command: 'flutter',
        includeDev: false,
        dryRun: false,
        output: output,
        errorOutput: errorOutput,
        executable: sdk.pubSdk.executable('flutter'),
        fetchVersions: (_) async => ['1.9.0', '2.0.0-rc.1'],
      );

      expect(sdk.calls.map((c) => '${c.executable} ${c.arguments}'), [
        'flutter pub outdated --json --show-all',
      ]);
      expect(output.toString(), isEmpty);
      expect(report.attempted, 0);
      expect(report.skippedUpToDate, 1);
      expect(report.skippedPrerelease, 1);
      expect(report.skippedKind, 1);
      expect(report.heldBack.map((h) => h.name), ['http']);
    });
  }, skip: fakeSdkSkip);
}
