import 'dart:io';

import 'package:pubup/src/outdated_runner.dart';
import 'package:pubup/src/version_resolver.dart';
import 'package:pubup/src/workspace_updater.dart';
import 'package:test/test.dart';

Future<List<OutdatedPackage>> _fakeOutdatedFetcher(
  String command,
  Directory packageDir,
) async {
  return [
    const OutdatedPackage(
      package: 'shared_dep',
      kind: 'direct',
      currentVersion: '1.0.0',
      resolvableVersion: '1.2.0',
    ),
  ];
}

Future<List<OutdatedPackage>> _fakeMajorBumpOutdatedFetcher(
  String command,
  Directory packageDir,
) async {
  return [
    const OutdatedPackage(
      package: 'shared_dep',
      kind: 'direct',
      currentVersion: '1.0.0',
      resolvableVersion: '2.0.0',
    ),
  ];
}

Future<List<OutdatedPackage>> _fakeTwoDepOutdatedFetcher(
  String command,
  Directory packageDir,
) async {
  return [
    const OutdatedPackage(
      package: 'shared_dep',
      kind: 'direct',
      currentVersion: '1.0.0',
      resolvableVersion: '1.2.0',
    ),
    const OutdatedPackage(
      package: 'other_dep',
      kind: 'direct',
      currentVersion: '2.0.0',
      resolvableVersion: '2.1.0',
    ),
  ];
}

void main() {
  late Directory tempDir;
  var pubGetCalls = 0;
  var pubGetResults = <int>[];

  Future<ProcessResult> fakePubGetRunner(
    String command,
    Directory workingDirectory,
  ) async {
    pubGetCalls++;
    final exitCode = pubGetResults.isNotEmpty ? pubGetResults.removeAt(0) : 0;
    if (exitCode != 0) {
      return ProcessResult(0, exitCode, '', 'version solving failed');
    }
    return ProcessResult(0, 0, 'Got dependencies!', '');
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pubup_ws_updater_');
    pubGetCalls = 0;
    pubGetResults = [];
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  void writeFile(String relativePath, String content) {
    final file = File('${tempDir.path}/$relativePath');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  Directory memberDir(String relativePath) =>
      Directory('${tempDir.path}/$relativePath');

  group('runUpdatesForWorkspace', () {
    test('dry-run prints coordinated updates without writing files', () async {
      writeFile('pubspec.yaml', _rootPubspec());
      writeFile('packages/pkg_a/pubspec.yaml', _memberPubspec('pkg_a'));
      writeFile('packages/pkg_b/pubspec.yaml', _memberPubspec('pkg_b'));

      final output = StringBuffer();
      final report = await runUpdatesForWorkspace(
        repoRoot: tempDir,
        scanTargets: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        allWorkspaceDirs: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        includeDev: true,
        dryRun: true,
        output: output,
        errorOutput: StringBuffer(),
        pubGetRunner: fakePubGetRunner,
        outdatedPackagesFetcher: _fakeOutdatedFetcher,
      );

      expect(pubGetCalls, 0);
      expect(report.attempted, 1);
      expect(report.changed, 3);
      final printed = output.toString();
      expect(printed, contains('shared_dep'));
      expect(printed, contains('^1.0.0'));
      expect(printed, contains('^1.2.0'));
      expect(printed, contains('3 members'));
      expect(
        File('${tempDir.path}/pubspec.yaml').readAsStringSync(),
        contains('shared_dep: ^1.0.0'),
      );
    });

    test('big-batch happy path runs pub get once for all coordinated deps',
        () async {
      writeFile('pubspec.yaml', _rootPubspec());
      writeFile('packages/pkg_a/pubspec.yaml', _memberPubspec('pkg_a'));
      writeFile('packages/pkg_b/pubspec.yaml', _memberPubspec('pkg_b'));

      final report = await runUpdatesForWorkspace(
        repoRoot: tempDir,
        scanTargets: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        allWorkspaceDirs: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        includeDev: true,
        dryRun: false,
        output: StringBuffer(),
        errorOutput: StringBuffer(),
        pubGetRunner: fakePubGetRunner,
        outdatedPackagesFetcher: _fakeOutdatedFetcher,
      );

      expect(pubGetCalls, 1);
      expect(report.failed, 0);
      expect(report.failures, isEmpty);
      expect(report.changed, 3);
      for (final path in [
        'pubspec.yaml',
        'packages/pkg_a/pubspec.yaml',
        'packages/pkg_b/pubspec.yaml',
      ]) {
        expect(
          File('${tempDir.path}/$path').readAsStringSync(),
          contains('shared_dep: ^1.2.0'),
        );
      }
    });

    test('big-batch happy path updates two deps with one pub get', () async {
      writeFile('pubspec.yaml', _rootPubspecTwoDeps());
      writeFile('packages/pkg_a/pubspec.yaml', _memberPubspecTwoDeps('pkg_a'));
      writeFile('packages/pkg_b/pubspec.yaml', _memberPubspecTwoDeps('pkg_b'));

      final report = await runUpdatesForWorkspace(
        repoRoot: tempDir,
        scanTargets: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        allWorkspaceDirs: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        includeDev: true,
        dryRun: false,
        output: StringBuffer(),
        errorOutput: StringBuffer(),
        pubGetRunner: fakePubGetRunner,
        outdatedPackagesFetcher: _fakeTwoDepOutdatedFetcher,
      );

      expect(pubGetCalls, 1);
      expect(report.attempted, 2);
      expect(report.failed, 0);
      expect(report.changed, 6);
      for (final path in [
        'pubspec.yaml',
        'packages/pkg_a/pubspec.yaml',
        'packages/pkg_b/pubspec.yaml',
      ]) {
        final content = File('${tempDir.path}/$path').readAsStringSync();
        expect(content, contains('shared_dep: ^1.2.0'));
        expect(content, contains('other_dep: ^2.1.0'));
      }
    });

    test('big-batch fails then per-dep fallback succeeds for all', () async {
      writeFile('pubspec.yaml', _rootPubspecTwoDeps());
      writeFile('packages/pkg_a/pubspec.yaml', _memberPubspecTwoDeps('pkg_a'));
      writeFile('packages/pkg_b/pubspec.yaml', _memberPubspecTwoDeps('pkg_b'));

      pubGetResults = [1, 0, 0];

      final errors = StringBuffer();
      final report = await runUpdatesForWorkspace(
        repoRoot: tempDir,
        scanTargets: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        allWorkspaceDirs: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        includeDev: true,
        dryRun: false,
        output: StringBuffer(),
        errorOutput: errors,
        pubGetRunner: fakePubGetRunner,
        outdatedPackagesFetcher: _fakeTwoDepOutdatedFetcher,
      );

      expect(pubGetCalls, 3);
      expect(report.failed, 0);
      expect(errors.toString(), contains('Big-batch pub get failed'));
      for (final path in [
        'pubspec.yaml',
        'packages/pkg_a/pubspec.yaml',
        'packages/pkg_b/pubspec.yaml',
      ]) {
        final content = File('${tempDir.path}/$path').readAsStringSync();
        expect(content, contains('shared_dep: ^1.2.0'));
        expect(content, contains('other_dep: ^2.1.0'));
      }
    });

    test('big-batch fails then one dep fails individually', () async {
      writeFile('pubspec.yaml', _rootPubspecTwoDeps());
      writeFile('packages/pkg_a/pubspec.yaml', _memberPubspecTwoDeps('pkg_a'));
      writeFile('packages/pkg_b/pubspec.yaml', _memberPubspecTwoDeps('pkg_b'));

      // Big batch fails; per-dep order is sorted by name: other_dep, shared_dep.
      pubGetResults = [1, 1, 0];

      final report = await runUpdatesForWorkspace(
        repoRoot: tempDir,
        scanTargets: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        allWorkspaceDirs: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        includeDev: true,
        dryRun: false,
        output: StringBuffer(),
        errorOutput: StringBuffer(),
        pubGetRunner: fakePubGetRunner,
        outdatedPackagesFetcher: _fakeTwoDepOutdatedFetcher,
      );

      expect(pubGetCalls, 3);
      expect(report.failed, 1);
      expect(report.failures, hasLength(1));
      expect(report.failures.first, contains('other_dep'));

      final root = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
      expect(root, contains('shared_dep: ^1.2.0'));
      expect(root, contains('other_dep: ^2.0.0'));
    });

    test('reverts all pubspecs when big batch and per-dep retry both fail',
        () async {
      writeFile('pubspec.yaml', _rootPubspec());
      writeFile('packages/pkg_a/pubspec.yaml', _memberPubspec('pkg_a'));
      pubGetResults = [1, 1];

      final report = await runUpdatesForWorkspace(
        repoRoot: tempDir,
        scanTargets: [tempDir, memberDir('packages/pkg_a')],
        allWorkspaceDirs: [tempDir, memberDir('packages/pkg_a')],
        includeDev: true,
        dryRun: false,
        output: StringBuffer(),
        errorOutput: StringBuffer(),
        pubGetRunner: fakePubGetRunner,
        outdatedPackagesFetcher: _fakeOutdatedFetcher,
      );

      expect(pubGetCalls, 2);
      expect(report.failed, 1);
      expect(
        File('${tempDir.path}/pubspec.yaml').readAsStringSync(),
        contains('shared_dep: ^1.0.0'),
      );
      expect(
        File('${tempDir.path}/packages/pkg_a/pubspec.yaml').readAsStringSync(),
        contains('shared_dep: ^1.0.0'),
      );
    });

    test('reports status during scan, pub get, and per-dep retry', () async {
      writeFile('pubspec.yaml', _rootPubspecTwoDeps());
      writeFile('packages/pkg_a/pubspec.yaml', _memberPubspecTwoDeps('pkg_a'));
      writeFile('packages/pkg_b/pubspec.yaml', _memberPubspecTwoDeps('pkg_b'));

      // Big batch fails; per-dep retries both succeed.
      pubGetResults = [1, 0, 0];

      final statusEvents = <String?>[];
      await runUpdatesForWorkspace(
        repoRoot: tempDir,
        scanTargets: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        allWorkspaceDirs: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        includeDev: true,
        dryRun: false,
        output: StringBuffer(),
        errorOutput: StringBuffer(),
        pubGetRunner: fakePubGetRunner,
        outdatedPackagesFetcher: _fakeTwoDepOutdatedFetcher,
        onStatus: statusEvents.add,
      );

      final messages = statusEvents.whereType<String>().toList(growable: false);

      expect(
        messages.where((m) => m.startsWith('Scanning')).toList(),
        [
          'Scanning . (1/3)',
          'Scanning packages/pkg_a (2/3)',
          'Scanning packages/pkg_b (3/3)',
        ],
      );
      expect(messages, contains(startsWith('Running ')));
      expect(messages.where((m) => m.startsWith('Retrying')).length, 2);
      // The reporter should be cleared (null) at least once before output is
      // printed and once at the end of the per-dep retry loop.
      expect(statusEvents.where((m) => m == null).length, greaterThan(1));
      // Last event must be a clear so the indicator never lingers.
      expect(statusEvents.last, isNull);
    });

    test('bumpLevel=minor picks in-bound version via fetchVersions', () async {
      writeFile('pubspec.yaml', _rootPubspec());
      writeFile('packages/pkg_a/pubspec.yaml', _memberPubspec('pkg_a'));
      writeFile('packages/pkg_b/pubspec.yaml', _memberPubspec('pkg_b'));

      final report = await runUpdatesForWorkspace(
        repoRoot: tempDir,
        scanTargets: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        allWorkspaceDirs: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        includeDev: true,
        dryRun: false,
        output: StringBuffer(),
        errorOutput: StringBuffer(),
        bumpLevel: BumpLevel.minor,
        fetchVersions: (name) async {
          expect(name, 'shared_dep');
          return ['1.0.0', '1.4.0', '1.9.0', '2.0.0'];
        },
        pubGetRunner: fakePubGetRunner,
        outdatedPackagesFetcher: _fakeMajorBumpOutdatedFetcher,
      );

      expect(report.failed, 0);
      expect(report.changed, 3);
      for (final path in [
        'pubspec.yaml',
        'packages/pkg_a/pubspec.yaml',
        'packages/pkg_b/pubspec.yaml',
      ]) {
        expect(
          File('${tempDir.path}/$path').readAsStringSync(),
          contains('shared_dep: ^1.9.0'),
        );
      }
    });

    test('bumpLevel=minor records skipped when no in-bound version exists',
        () async {
      writeFile('pubspec.yaml', _rootPubspec());
      writeFile('packages/pkg_a/pubspec.yaml', _memberPubspec('pkg_a'));

      final report = await runUpdatesForWorkspace(
        repoRoot: tempDir,
        scanTargets: [tempDir, memberDir('packages/pkg_a')],
        allWorkspaceDirs: [tempDir, memberDir('packages/pkg_a')],
        includeDev: true,
        dryRun: false,
        output: StringBuffer(),
        errorOutput: StringBuffer(),
        bumpLevel: BumpLevel.minor,
        fetchVersions: (_) async => ['1.0.0', '2.0.0'],
        pubGetRunner: fakePubGetRunner,
        outdatedPackagesFetcher: _fakeMajorBumpOutdatedFetcher,
      );

      expect(report.skippedByBumpFilter, 2);
      expect(report.attempted, 0);
      expect(report.changed, 0);
      expect(pubGetCalls, 0);
      expect(
        File('${tempDir.path}/pubspec.yaml').readAsStringSync(),
        contains('shared_dep: ^1.0.0'),
      );
    });

    test('skips coordinated dep when --package filter excludes a declarer',
        () async {
      writeFile('pubspec.yaml', _rootPubspec());
      writeFile('packages/pkg_a/pubspec.yaml', _memberPubspec('pkg_a'));
      writeFile('packages/pkg_b/pubspec.yaml', _memberPubspec('pkg_b'));

      final errors = StringBuffer();
      final report = await runUpdatesForWorkspace(
        repoRoot: tempDir,
        scanTargets: [tempDir],
        allWorkspaceDirs: [
          tempDir,
          memberDir('packages/pkg_a'),
          memberDir('packages/pkg_b'),
        ],
        includeDev: true,
        dryRun: false,
        output: StringBuffer(),
        errorOutput: errors,
        pubGetRunner: fakePubGetRunner,
        outdatedPackagesFetcher: _fakeOutdatedFetcher,
      );

      expect(report.skippedFilteredCoordination, 1);
      expect(pubGetCalls, 0);
      expect(errors.toString(), contains('outside --package filter'));
      expect(
        File('${tempDir.path}/pubspec.yaml').readAsStringSync(),
        contains('shared_dep: ^1.0.0'),
      );
    });
  });
}

String _rootPubspec() => '''
name: root_app
environment:
  sdk: ">=3.0.0 <4.0.0"
workspace:
  - packages/pkg_a
  - packages/pkg_b
dependencies:
  shared_dep: ^1.0.0
''';

String _memberPubspec(String name) => '''
name: $name
resolution: workspace
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  shared_dep: ^1.0.0
''';

String _rootPubspecTwoDeps() => '''
name: root_app
environment:
  sdk: ">=3.0.0 <4.0.0"
workspace:
  - packages/pkg_a
  - packages/pkg_b
dependencies:
  shared_dep: ^1.0.0
  other_dep: ^2.0.0
''';

String _memberPubspecTwoDeps(String name) => '''
name: $name
resolution: workspace
environment:
  sdk: ">=3.0.0 <4.0.0"
dependencies:
  shared_dep: ^1.0.0
  other_dep: ^2.0.0
''';
