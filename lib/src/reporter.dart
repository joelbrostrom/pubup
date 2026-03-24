/// Report for a single workspace package after running updates.
class PackageReport {
  /// Creates a [PackageReport].
  PackageReport({
    required this.packageDir,
    required this.command,
  });

  /// The absolute path to the package directory.
  final String packageDir;

  /// The pub command used (`"dart"` or `"flutter"`).
  final String command;

  /// Number of dependencies where an update was attempted.
  int attempted = 0;

  /// Number of dependencies successfully updated.
  int changed = 0;

  /// Number of dependencies already at the target constraint.
  int skippedUpToDate = 0;

  /// Number of dev dependencies skipped because `--no-dev` was used.
  int skippedKind = 0;

  /// Number of dependencies skipped due to non-hosted source.
  int skippedNonHosted = 0;

  /// Number of dependencies skipped due to non-standard constraints.
  int skippedNonstandard = 0;

  /// Number of dependencies that could not be classified.
  int skippedUnknown = 0;

  /// Number of dependencies where the update command failed.
  int failed = 0;

  /// Failure messages for each failed dependency.
  final List<String> failures = [];
}

/// Prints a summary of all [reports] to [output].
///
/// Returns `1` if any failures occurred, `0` otherwise.
int printReport(
  List<PackageReport> reports, {
  required bool dryRun,
  required StringSink output,
}) {
  output.writeln();
  output.writeln('Summary');
  output.writeln('=======');

  var totalAttempted = 0;
  var totalChanged = 0;
  var totalFailed = 0;
  var totalSkippedUpToDate = 0;
  var totalSkippedKind = 0;
  var totalSkippedNonHosted = 0;
  var totalSkippedNonstandard = 0;
  var totalSkippedUnknown = 0;

  for (final report in reports) {
    totalAttempted += report.attempted;
    totalChanged += report.changed;
    totalFailed += report.failed;
    totalSkippedUpToDate += report.skippedUpToDate;
    totalSkippedKind += report.skippedKind;
    totalSkippedNonHosted += report.skippedNonHosted;
    totalSkippedNonstandard += report.skippedNonstandard;
    totalSkippedUnknown += report.skippedUnknown;

    output.writeln(
      '- ${report.packageDir}: '
      'changed=${report.changed}, failed=${report.failed}',
    );
    output.writeln(
      '    attempted=${report.attempted}, '
      'skipped_up_to_date=${report.skippedUpToDate}, '
      'skipped_kind=${report.skippedKind}, '
      'skipped_non_hosted=${report.skippedNonHosted}, '
      'skipped_nonstandard=${report.skippedNonstandard}, '
      'skipped_unknown=${report.skippedUnknown}',
    );
    for (final failure in report.failures) {
      output.writeln('    failure: $failure');
    }
  }

  output.writeln();
  output.writeln(
    'Totals: attempted=$totalAttempted, changed=$totalChanged, '
    'failed=$totalFailed, skipped_up_to_date=$totalSkippedUpToDate, '
    'skipped_kind=$totalSkippedKind, '
    'skipped_non_hosted=$totalSkippedNonHosted, '
    'skipped_nonstandard=$totalSkippedNonstandard, '
    'skipped_unknown=$totalSkippedUnknown',
  );

  if (dryRun) {
    output.writeln('Dry-run mode: no files were changed.');
  }

  return totalFailed > 0 ? 1 : 0;
}
