import 'dart:io';

import 'package:pubup/src/candidate_collector.dart';
import 'package:pubup/src/outdated_runner.dart';
import 'package:pubup/src/pubspec_parser.dart';
import 'package:pubup/src/reporter.dart';

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
}) async {
  final pubspec = File('${packageDir.path}/pubspec.yaml');
  final deps = parseDependencyEntries(pubspec);
  final outdated = await getOutdatedPackages(command, packageDir);
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

  final dryLabel = dryRun ? ' [dry-run]' : '';
  for (final candidate in result.candidates) {
    report.attempted++;
    output.writeln(
      '  - ${candidate.kind.padRight(6)} ${candidate.name}: '
      '${candidate.declaredConstraint} -> ${candidate.targetConstraint} '
      '(resolved=${candidate.currentVersion}, '
      'resolvable=${candidate.resolvableVersion})$dryLabel',
    );
  }

  if (dryRun) {
    report.changed += result.candidates.length;
    return report;
  }

  final specs = result.candidates.map(_specFor).toList(growable: false);

  final batchResult = await Process.run(
    command,
    ['pub', 'add', ...specs],
    workingDirectory: packageDir.path,
  );

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

  for (final candidate in result.candidates) {
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

  return report;
}

String _specFor(CandidateUpdate candidate) => candidate.kind == 'dev'
    ? 'dev:${candidate.name}:${candidate.targetConstraint}'
    : '${candidate.name}:${candidate.targetConstraint}';
