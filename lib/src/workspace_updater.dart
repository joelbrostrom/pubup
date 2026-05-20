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
/// Dependencies shared by multiple members are updated atomically. Workspace
/// mode tries one big batch (all rewrites + a single root `pub get`) first,
/// then falls back to per-dependency batches when resolution fails.
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

  final sortedKeys = candidatesByKey.keys.toList()..sort();

  final rowMeta = <String, _RowMeta>{};
  for (final key in sortedKeys) {
    final members = candidatesByKey[key]!;
    final first = members.first.candidate;
    final declarers = _findDeclarers(
      allWorkspaceDirs: allWorkspaceDirs,
      repoRoot: repoRoot,
      packageName: first.name,
      kind: first.kind,
    );
    final fromConstraint =
        members.map((m) => m.candidate.declaredConstraint).toSet().join(', ');
    rowMeta[key] = _RowMeta(
      candidate: first,
      declarers: declarers,
      fromConstraint: fromConstraint,
    );
  }

  final columns = CandidateColumns.fromRows(
    names: rowMeta.values.map((m) => m.candidate.name),
    fromConstraints: rowMeta.values.map((m) => m.fromConstraint),
    toConstraints: rowMeta.values.map((m) => m.candidate.targetConstraint),
  );

  final eligibleRows = <_RowMeta>[];

  for (final key in sortedKeys) {
    final meta = rowMeta[key]!;
    final first = meta.candidate;
    final allDeclarers = meta.declarers;

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

    eligibleRows.add(meta);

    final memberCount = allDeclarers.length;
    final trailing = '$memberCount ${memberCount == 1 ? "member" : "members"}';

    report.attempted++;
    output.writeln(
      formatCandidateRow(
        columns: columns,
        name: first.name,
        kind: first.kind,
        fromConstraint: meta.fromConstraint,
        toConstraint: first.targetConstraint,
        trailing: trailing,
      ),
    );
  }

  if (eligibleRows.isEmpty) {
    return report;
  }

  if (dryRun) {
    for (final row in eligibleRows) {
      report.changed += row.declarers.length;
    }
    return report;
  }

  final bigBatch = await _applyCoordinatedBatch(
    rows: eligibleRows,
    command: command,
    repoRoot: repoRoot,
    runPubGet: runPubGet,
  );

  if (bigBatch.succeeded) {
    report.changed += bigBatch.membersChanged;
    return report;
  }

  errorOutput.writeln(
    '  ! Big-batch pub get failed; retrying ${eligibleRows.length} '
    'coordinated updates individually to identify failures...',
  );

  for (final row in eligibleRows) {
    final single = await _applyCoordinatedBatch(
      rows: [row],
      command: command,
      repoRoot: repoRoot,
      runPubGet: runPubGet,
    );

    if (single.succeeded) {
      report.changed += single.membersChanged;
    } else {
      report.failed++;
      final name = row.candidate.name;
      final message = single.failureOutput ??
          'could not rewrite constraint in one or more pubspec.yaml files '
              '(non-standard constraint form).';
      report.failures.add('$name: ${message.trim()}');
    }
  }

  return report;
}

class _RowMeta {
  const _RowMeta({
    required this.candidate,
    required this.declarers,
    required this.fromConstraint,
  });

  final CandidateUpdate candidate;
  final List<_Declarer> declarers;
  final String fromConstraint;
}

class _BatchOutcome {
  const _BatchOutcome({
    required this.succeeded,
    this.failureOutput,
    this.membersChanged = 0,
  });

  final bool succeeded;
  final String? failureOutput;
  final int membersChanged;
}

Future<_BatchOutcome> _applyCoordinatedBatch({
  required List<_RowMeta> rows,
  required String command,
  required Directory repoRoot,
  required PubGetRunner runPubGet,
}) async {
  if (rows.isEmpty) {
    return const _BatchOutcome(succeeded: true, membersChanged: 0);
  }

  final snapshots = <String, String>{};
  var membersChanged = 0;

  for (final row in rows) {
    membersChanged += row.declarers.length;
    for (final declarer in row.declarers) {
      final path = '${declarer.packageDir.path}/pubspec.yaml';
      snapshots.putIfAbsent(
        path,
        () => File(path).readAsStringSync(),
      );
    }
  }

  for (final row in rows) {
    final first = row.candidate;
    final section = first.kind == 'dev' ? 'dev_dependencies' : 'dependencies';

    for (final declarer in row.declarers) {
      final path = '${declarer.packageDir.path}/pubspec.yaml';
      final file = File(path);
      final rewrite = rewriteConstraint(
        content: file.readAsStringSync(),
        section: section,
        packageName: first.name,
        newConstraint: first.targetConstraint,
      );
      if (!rewrite.changed) {
        _restoreSnapshots(snapshots);
        return _BatchOutcome(
          succeeded: false,
          failureOutput:
              'could not rewrite constraint in one or more pubspec.yaml '
              'files (non-standard constraint form).',
        );
      }
      file.writeAsStringSync(rewrite.content);
    }
  }

  final pubGetResult = await runPubGet(command, repoRoot);
  if (pubGetResult.exitCode != 0) {
    _restoreSnapshots(snapshots);
    final failureOutput = (pubGetResult.stderr as String).trim().isNotEmpty
        ? pubGetResult.stderr as String
        : pubGetResult.stdout as String;
    return _BatchOutcome(
      succeeded: false,
      failureOutput: failureOutput.trim(),
    );
  }

  return _BatchOutcome(
    succeeded: true,
    membersChanged: membersChanged,
  );
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
