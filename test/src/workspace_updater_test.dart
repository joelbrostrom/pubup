import 'dart:io';

import 'package:pubup/src/outdated_runner.dart';
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

void main() {
  late Directory tempDir;
  var pubGetCalls = 0;
  var pubGetShouldFail = false;

  Future<ProcessResult> fakePubGetRunner(
    String command,
    Directory workingDirectory,
  ) async {
    pubGetCalls++;
    if (pubGetShouldFail) {
      return ProcessResult(0, 1, '', 'version solving failed');
    }
    return ProcessResult(0, 0, 'Got dependencies!', '');
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pubup_ws_updater_');
    pubGetCalls = 0;
    pubGetShouldFail = false;
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
      expect(output.toString(), contains('coordinated'));
      expect(
        File('${tempDir.path}/pubspec.yaml').readAsStringSync(),
        contains('shared_dep: ^1.0.0'),
      );
    });

    test('rewrites all declarers and runs pub get once per dep', () async {
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

    test('reverts all pubspecs when pub get fails', () async {
      writeFile('pubspec.yaml', _rootPubspec());
      writeFile('packages/pkg_a/pubspec.yaml', _memberPubspec('pkg_a'));
      pubGetShouldFail = true;

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
