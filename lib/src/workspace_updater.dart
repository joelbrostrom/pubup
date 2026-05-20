import 'dart:io';

import 'package:pubup/src/candidate_collector.dart';
import 'package:pubup/src/constraint_rewriter.dart';
import 'package:pubup/src/outdated_runner.dart';
import 'package:pubup/src/pubspec_parser.dart';
import 'package:pubup/src/reporter.dart';

/// A dependency update candidate tied to a specific workspace member.
class WorkspaceMemberCandidate {
  /// Creates a [WorkspaceMemberCandidate].
  const WorkspaceMemberCandidate({
    required this.packageDir,
    required this.relativePath,
    required this.candidate,
  });

  /// The workspace member directory.
  final Directory packageDir;

  /// Path relative to the workspace root (`.` for root).
  final String relativePath;

  /// The update candidate for this member.
  final CandidateUpdate candidate;
}

/// Fetches outdated package rows for a workspace member.
typedef OutdatedPackagesFetcher = Future<List<OutdatedPackage>> Function(
  String command,
  Directory packageDir,
);

/// Runs coordinated dependency updates across a Dart pub workspace.
///
/// Dependencies shared by multiple members are updated atomically: every
/// declaring `pubspec.yaml` is rewritten, then a single root-level `pub get`
/// validates the workspace graph.
Future<WorkspaceReport> runUpdatesForWorkspace({
  required Directory repoRoot,
  required List<Directory> scanTargets,
  required List<Directory> allWorkspaceDirs,
  required bool includeDev,
  required bool dryRun,
  required StringSink output,
  required StringSink errorOutput,
  PubGetRunner? pubGetRunner,
  OutdatedPackagesFetcher? outdatedPackagesFetcher,
}) async {
  final runPubGet = pubGetRunner ?? _defaultPubGetRunner;
  final fetchOutdated = outdatedPackagesFetcher ?? getOutdatedPackages;
  final rootPubspec = File('${repoRoot.path}/pubspec.yaml');
  final command = isFlutterPackage(rootPubspec) ? 'flutter' : 'dart';
  final usingPackageFilter = scanTargets.length < allWorkspaceDirs.length;

  final report = WorkspaceReport(repoRoot: repoRoot.path, command: command);
  final candidatesByKey = <String, List<WorkspaceMemberCandidate>>{};

  for (final target in scanTargets) {
    final pubspec = File('${target.path}/pubspec.yaml');
    final memberCommand = isFlutterPackage(pubspec) ? 'flutter' : 'dart';
    final rel = _relativePath(target.path, repoRoot.path);
    final deps = parseDependencyEntries(pubspec);

    List<OutdatedPackage> outdated;
    try {
      outdated = await fetchOutdated(memberCommand, target);
    } on Exception catch (e) {
      report.scanFailures.add('$rel: $e');
      errorOutput.writeln('  ! Failed package scan ($rel): $e');
      continue;
    }

    final result = collectCandidates(
      outdatedPackages: outdated,
      deps: deps,
      includeDev: includeDev,
    );

    report.skippedUpToDate += result.report.skippedUpToDate;
    report.skippedKind += result.report.skippedKind;
    report.skippedNonHosted += result.report.skippedNonHosted;
    report.skippedNonstandard += result.report.skippedNonstandard;
    report.skippedUnknown += result.report.skippedUnknown;

    for (final candidate in result.candidates) {
      final key = _coordinationKey(candidate.name, candidate.kind);
      candidatesByKey.putIfAbsent(key, () => []).add(
            WorkspaceMemberCandidate(
              packageDir: target,
              relativePath: rel,
              candidate: candidate,
            ),
          );
    }
  }

  if (candidatesByKey.isEmpty) {
    return report;
  }

  final dryLabel = dryRun ? ' [dry-run]' : '';
  final sortedKeys = candidatesByKey.keys.toList()..sort();

  for (final key in sortedKeys) {
    final members = candidatesByKey[key]!;
    final first = members.first.candidate;
    final section = first.kind == 'dev' ? 'dev_dependencies' : 'dependencies';

    final allDeclarers = _findDeclarers(
      allWorkspaceDirs: allWorkspaceDirs,
      repoRoot: repoRoot,
      packageName: first.name,
      kind: first.kind,
    );

    if (usingPackageFilter) {
      final scanPaths = scanTargets.map((d) => d.path).toSet();
      final outsideFilter = allDeclarers
          .where((d) => !scanPaths.contains(d.packageDir.path))
          .toList();
      if (outsideFilter.isNotEmpty) {
        final names = outsideFilter.map((d) => d.relativePath).join(', ');
        report.skippedFilteredCoordination++;
        errorOutput.writeln(
          '  ! Skipping coordinated ${first.name}: also declared in '
          'members outside --package filter ($names). '
          'Run without --package to update this dependency workspace-wide.',
        );
        continue;
      }
    }

    final targetConstraint = first.targetConstraint;
    final sampleOld =
        members.map((m) => m.candidate.declaredConstraint).toSet().join(', ');

    report.attempted++;
    output.writeln(
      '  - coordinated ${first.kind.padRight(6)} ${first.name}: '
      '$sampleOld -> $targetConstraint '
      '(resolved=${first.currentVersion}, resolvable=${first.resolvableVersion}, '
      'members=${allDeclarers.length})$dryLabel',
    );

    if (dryRun) {
      report.changed += allDeclarers.length;
      continue;
    }

    final snapshots = <String, String>{};
    for (final declarer in allDeclarers) {
      final path = '${declarer.packageDir.path}/pubspec.yaml';
      snapshots[path] = File(path).readAsStringSync();
    }

    var rewriteFailed = false;
    for (final declarer in allDeclarers) {
      final path = '${declarer.packageDir.path}/pubspec.yaml';
      final file = File(path);
      final rewrite = rewriteConstraint(
        content: file.readAsStringSync(),
        section: section,
        packageName: first.name,
        newConstraint: targetConstraint,
      );
      if (!rewrite.changed) {
        rewriteFailed = true;
        break;
      }
      file.writeAsStringSync(rewrite.content);
    }

    if (rewriteFailed) {
      _restoreSnapshots(snapshots);
      report.failed++;
      report.failures.add(
        '${first.name}: could not rewrite constraint in one or more pubspec.yaml '
        'files (non-standard constraint form).',
      );
      continue;
    }

    final pubGetResult = await runPubGet(command, repoRoot);
    if (pubGetResult.exitCode != 0) {
      _restoreSnapshots(snapshots);
      report.failed++;
      final failureOutput = (pubGetResult.stderr as String).trim().isNotEmpty
          ? pubGetResult.stderr as String
          : pubGetResult.stdout as String;
      report.failures.add('${first.name}: ${failureOutput.trim()}');
      continue;
    }

    report.changed += allDeclarers.length;
  }

  return report;
}

/// Runs `pub get` at the workspace root.
typedef PubGetRunner = Future<ProcessResult> Function(
  String command,
  Directory workingDirectory,
);

Future<ProcessResult> _defaultPubGetRunner(
  String command,
  Directory workingDirectory,
) {
  return Process.run(
    command,
    ['pub', 'get'],
    workingDirectory: workingDirectory.path,
  );
}

String _coordinationKey(String packageName, String kind) =>
    '$kind:$packageName';

String _relativePath(String child, String parent) {
  if (child == parent) return '.';
  final normalized =
      child.startsWith(parent) ? child.substring(parent.length) : child;
  final trimmed = normalized.startsWith('/') || normalized.startsWith(r'\')
      ? normalized.substring(1)
      : normalized;
  return trimmed.isEmpty ? '.' : trimmed;
}

class _Declarer {
  const _Declarer({
    required this.packageDir,
    required this.relativePath,
  });

  final Directory packageDir;
  final String relativePath;
}

List<_Declarer> _findDeclarers({
  required List<Directory> allWorkspaceDirs,
  required Directory repoRoot,
  required String packageName,
  required String kind,
}) {
  final declarers = <_Declarer>[];

  for (final dir in allWorkspaceDirs) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    final deps = parseDependencyEntries(pubspec);
    final section = kind == 'dev' ? deps.dev : deps.direct;
    final entry = section[packageName];
    if (entry == null) continue;
    if (const {'path', 'git', 'sdk'}.contains(entry.source)) continue;

    declarers.add(
      _Declarer(
        packageDir: dir,
        relativePath: _relativePath(dir.path, repoRoot.path),
      ),
    );
  }

  return declarers;
}

void _restoreSnapshots(Map<String, String> snapshots) {
  for (final entry in snapshots.entries) {
    File(entry.key).writeAsStringSync(entry.value);
  }
}
