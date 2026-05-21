import 'dart:io';

import 'package:pubup/src/candidate_collector.dart';
import 'package:pubup/src/outdated_runner.dart';
import 'package:pubup/src/pubspec_parser.dart';
import 'package:pubup/src/reporter.dart';
import 'package:pubup/src/status_line.dart';

/// Runs the full update workflow for a single [packageDir].
///
/// Returns a [PackageReport] summarising what was changed, skipped, or failed.
///
/// When [dryRun] is `true`, candidates are printed but no files are modified.
///
/// All candidates for the package are applied in a single `pub add` invocation
/// so the pub solver only runs once per package instead of once per dependency.
/// If the batched call fails (e.g. one dep cannot be resolved), the updater
/// falls back to per-candidate `pub add` calls to preserve accurate per-dep
/// failure attribution.
Future<PackageReport> runUpdatesForPackage({
  required Directory packageDir,
  required String command,
  required bool includeDev,
  required bool dryRun,
  required StringSink output,
  required StringSink errorOutput,
  StatusReporter? onStatus,
}) async {
  final reportStatus = onStatus ?? noopStatusReporter;
  final pubspec = File('${packageDir.path}/pubspec.yaml');
  final deps = parseDependencyEntries(pubspec);

  reportStatus('Scanning for outdated dependencies');
  final outdated = await getOutdatedPackages(command, packageDir);
  reportStatus(null);

  final result = collectCandidates(
    outdatedPackages: outdated,
    deps: deps,
    includeDev: includeDev,
  );

  final report = PackageReport(packageDir: packageDir.path, command: command)
    ..skippedUpToDate = result.report.skippedUpToDate
    ..skippedKind = result.report.skippedKind
    ..skippedNonHosted = result.report.skippedNonHosted
    ..skippedNonstandard = result.report.skippedNonstandard
    ..skippedUnknown = result.report.skippedUnknown;

  if (result.candidates.isEmpty) {
    return report;
  }

  final columns = CandidateColumns.fromRows(
    names: result.candidates.map((c) => c.name),
    fromConstraints: result.candidates.map((c) => c.declaredConstraint),
    toConstraints: result.candidates.map((c) => c.targetConstraint),
  );

  for (final candidate in result.candidates) {
    report.attempted++;
    output.writeln(
      formatCandidateRow(
        columns: columns,
        name: candidate.name,
        kind: candidate.kind,
        fromConstraint: candidate.declaredConstraint,
        toConstraint: candidate.targetConstraint,
        trailing: candidate.currentVersion != candidate.resolvableVersion
            ? '(was ${candidate.currentVersion})'
            : null,
      ),
    );
  }

  if (dryRun) {
    report.changed += result.candidates.length;
    return report;
  }

  final specs = result.candidates.map(_specFor).toList(growable: false);

  reportStatus('Running $command pub add');
  final batchResult = await Process.run(
    command,
    ['pub', 'add', ...specs],
    workingDirectory: packageDir.path,
  );
  reportStatus(null);

  if (batchResult.exitCode == 0) {
    report.changed += result.candidates.length;
    return report;
  }

  // Batched call failed (likely a single bad version blocking resolution).
  // Retry each candidate individually so we can report exactly which deps
  // succeeded and which failed.
  errorOutput.writeln(
    '  ! Batched update failed; retrying ${result.candidates.length} '
    'updates individually to identify failures...',
  );

  for (var i = 0; i < result.candidates.length; i++) {
    final candidate = result.candidates[i];
    reportStatus(
      'Retrying ${candidate.name} (${i + 1}/${result.candidates.length})',
    );
    final addResult = await Process.run(
      command,
      ['pub', 'add', _specFor(candidate)],
      workingDirectory: packageDir.path,
    );

    if (addResult.exitCode == 0) {
      report.changed++;
    } else {
      report.failed++;
      final failureOutput = (addResult.stderr as String).trim().isNotEmpty
          ? addResult.stderr as String
          : addResult.stdout as String;
      report.failures.add('${candidate.name}: ${failureOutput.trim()}');
    }
  }
  reportStatus(null);

  return report;
}

String _specFor(CandidateUpdate candidate) => candidate.kind == 'dev'
    ? 'dev:${candidate.name}:${candidate.targetConstraint}'
    : '${candidate.name}:${candidate.targetConstraint}';
