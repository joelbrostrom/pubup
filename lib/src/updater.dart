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

  for (final candidate in result.candidates) {
    report.attempted++;

    final depSpec = candidate.kind == 'dev'
        ? 'dev:${candidate.name}:${candidate.targetConstraint}'
        : '${candidate.name}:${candidate.targetConstraint}';

    final dryLabel = dryRun ? ' [dry-run]' : '';
    output.writeln(
      '  - ${candidate.kind.padRight(6)} ${candidate.name}: '
      '${candidate.declaredConstraint} -> ${candidate.targetConstraint} '
      '(resolved=${candidate.currentVersion}, '
      'resolvable=${candidate.resolvableVersion})$dryLabel',
    );

    if (dryRun) {
      report.changed++;
      continue;
    }

    final addResult = await Process.run(
      command,
      ['pub', 'add', depSpec],
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
