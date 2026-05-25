import 'dart:math' as math;

/// Maximum width for the package-name column when aligning rows.
///
/// Names longer than this are not truncated; they overflow their cell so
/// the rest of the table stays compact for the common case (typical 80-col
/// terminal). Tuned so a row with the largest realistic columns still fits:
/// 2 (indent) + 22 (name) + 2 + 6 (kind) + 2 + 18 (from) + 4 ` -> ` +
/// 8 (to) + 4 + 11 (trailing) ≈ 79.
const int _maxNameColumn = 22;

/// Maximum width for the "from" constraint column.
const int _maxFromColumn = 18;

/// Maximum width for the "to" constraint column (so trailing notes align).
const int _maxToColumn = 10;

/// Target width for word-wrapped failure detail lines.
const int _wrapWidth = 76;

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

  /// Number of dependencies skipped because the latest in-bound version is
  /// not above the current version (filtered by `--bump`).
  int skippedByBumpFilter = 0;

  /// Number of dependencies where the update command failed.
  int failed = 0;

  /// Failure messages for each failed dependency.
  final List<String> failures = [];
}

/// Report for a coordinated workspace update run.
class WorkspaceReport {
  /// Creates a [WorkspaceReport].
  WorkspaceReport({
    required this.repoRoot,
    required this.command,
  });

  /// The absolute path to the workspace root.
  final String repoRoot;

  /// The pub command used at the workspace root (`"dart"` or `"flutter"`).
  final String command;

  /// Number of coordinated dependencies where an update was attempted.
  int attempted = 0;

  /// Number of pubspec.yaml files successfully updated.
  int changed = 0;

  /// Number of coordinated dependencies that failed.
  int failed = 0;

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

  /// Number of dependencies skipped because the latest in-bound version is
  /// not above the current version (filtered by `--bump`).
  int skippedByBumpFilter = 0;

  /// Coordinated deps skipped because `--package` did not include all members.
  int skippedFilteredCoordination = 0;

  /// Failure messages for each failed coordinated dependency.
  final List<String> failures = [];

  /// Per-member scan failures (e.g. `pub outdated` errors).
  final List<String> scanFailures = [];
}

/// Pre-computed column widths used to align candidate rows in a table.
class CandidateColumns {
  /// Creates [CandidateColumns] with explicit widths.
  const CandidateColumns({
    required this.name,
    required this.from,
    required this.to,
  });

  /// An empty layout (zero widths) for tables with no rows.
  static const empty = CandidateColumns(name: 0, from: 0, to: 0);

  /// Width of the package-name column.
  final int name;

  /// Width of the "from" constraint column.
  final int from;

  /// Width of the "to" constraint column.
  final int to;

  /// Computes column widths from the actual values that will be rendered.
  ///
  /// Each column is sized to the longest value it must hold, capped at a
  /// reasonable maximum so a single outlier does not stretch the whole table.
  factory CandidateColumns.fromRows({
    required Iterable<String> names,
    required Iterable<String> fromConstraints,
    required Iterable<String> toConstraints,
  }) {
    int maxLen(Iterable<String> values) {
      var m = 0;
      for (final v in values) {
        if (v.length > m) m = v.length;
      }
      return m;
    }

    return CandidateColumns(
      name: math.min(maxLen(names), _maxNameColumn),
      from: math.min(maxLen(fromConstraints), _maxFromColumn),
      to: math.min(maxLen(toConstraints), _maxToColumn),
    );
  }
}

/// Formats a single candidate row using the pre-computed [columns].
///
/// All rows in the same table should share the same [columns] instance so
/// columns line up.
String formatCandidateRow({
  required CandidateColumns columns,
  required String name,
  required String kind,
  required String fromConstraint,
  required String toConstraint,
  String? trailing,
}) {
  final paddedName = name.padRight(columns.name);
  final paddedKind = kind.padRight(6);
  final paddedFrom = fromConstraint.padRight(columns.from);
  final paddedTo = toConstraint.padRight(columns.to);
  final core = '  $paddedName  $paddedKind  $paddedFrom  ->  $paddedTo';
  if (trailing == null || trailing.isEmpty) return core.trimRight();
  return '$core    $trailing';
}

/// Prints a summary of a [WorkspaceReport] to [output].
///
/// Returns `1` if any failures or scan failures occurred, `0` otherwise.
int printWorkspaceReport(
  WorkspaceReport report, {
  required bool dryRun,
  required StringSink output,
}) {
  _writeFailuresSection(
    output,
    report.failures,
    report.scanFailures.map((s) => 'scan failed: $s'),
  );

  output.writeln();
  output.writeln('Summary');
  output.writeln('-------');

  if (report.changed > 0) {
    final attempted = report.attempted;
    output.writeln(
      '  Updated  ${report.changed} '
      '${_pluralize("constraint", report.changed)} across '
      '$attempted ${_pluralize("dependency", attempted, "dependencies")}',
    );
  } else {
    output.writeln('  Updated  0');
  }

  output.writeln('  Failed   ${report.failed}');

  final skipDescription = _describeSkipped(
    upToDate: report.skippedUpToDate,
    kind: report.skippedKind,
    nonHosted: report.skippedNonHosted,
    nonstandard: report.skippedNonstandard,
    unknown: report.skippedUnknown,
    byBumpFilter: report.skippedByBumpFilter,
    filteredCoordination: report.skippedFilteredCoordination,
  );
  if (skipDescription.isNotEmpty) {
    output.writeln('  Skipped  $skipDescription');
  }

  if (dryRun) {
    output.writeln();
    output.writeln('Dry-run mode: no files were changed.');
  }

  final hasFailures = report.failed > 0 || report.scanFailures.isNotEmpty;
  return hasFailures ? 1 : 0;
}

/// Prints a summary of all [reports] to [output].
///
/// Returns `1` if any failures occurred, `0` otherwise.
int printReport(
  List<PackageReport> reports, {
  required bool dryRun,
  required StringSink output,
}) {
  final allFailures = [
    for (final r in reports) ...r.failures,
  ];
  _writeFailuresSection(output, allFailures, const []);

  output.writeln();
  output.writeln('Summary');
  output.writeln('-------');

  var totalChanged = 0;
  var totalFailed = 0;
  var totalSkippedUpToDate = 0;
  var totalSkippedKind = 0;
  var totalSkippedNonHosted = 0;
  var totalSkippedNonstandard = 0;
  var totalSkippedUnknown = 0;
  var totalSkippedByBumpFilter = 0;

  for (final r in reports) {
    totalChanged += r.changed;
    totalFailed += r.failed;
    totalSkippedUpToDate += r.skippedUpToDate;
    totalSkippedKind += r.skippedKind;
    totalSkippedNonHosted += r.skippedNonHosted;
    totalSkippedNonstandard += r.skippedNonstandard;
    totalSkippedUnknown += r.skippedUnknown;
    totalSkippedByBumpFilter += r.skippedByBumpFilter;
  }

  if (reports.length > 1) {
    for (final r in reports) {
      output.writeln(
        '  ${r.packageDir}: '
        'updated ${r.changed}, failed ${r.failed}',
      );
    }
    output.writeln();
  }

  output.writeln('  Updated  $totalChanged');
  output.writeln('  Failed   $totalFailed');

  final skipDescription = _describeSkipped(
    upToDate: totalSkippedUpToDate,
    kind: totalSkippedKind,
    nonHosted: totalSkippedNonHosted,
    nonstandard: totalSkippedNonstandard,
    unknown: totalSkippedUnknown,
    byBumpFilter: totalSkippedByBumpFilter,
  );
  if (skipDescription.isNotEmpty) {
    output.writeln('  Skipped  $skipDescription');
  }

  if (dryRun) {
    output.writeln();
    output.writeln('Dry-run mode: no files were changed.');
  }

  return totalFailed > 0 ? 1 : 0;
}

void _writeFailuresSection(
  StringSink output,
  Iterable<String> failures,
  Iterable<String> extraFailures,
) {
  final entries = [...failures, ...extraFailures];
  if (entries.isEmpty) return;

  final header = 'Failures (${entries.length})';
  output.writeln();
  output.writeln(header);
  output.writeln('-' * header.length);

  for (final entry in entries) {
    _writeFailure(output, entry);
  }
}

void _writeFailure(StringSink output, String failure) {
  final trimmed = failure.trim();
  final colonIndex = trimmed.indexOf(':');
  if (colonIndex == -1) {
    output.writeln();
    output.writeln('  $trimmed');
    return;
  }

  final name = trimmed.substring(0, colonIndex).trim();
  final rest = trimmed.substring(colonIndex + 1).trim();

  output.writeln();
  output.writeln('  $name:');
  if (rest.isEmpty) return;

  for (final line in _wrapText(rest, _wrapWidth)) {
    output.writeln('    $line');
  }
}

/// Word-wraps [text] to lines no longer than [width], preserving existing
/// line breaks as paragraph separators.
List<String> _wrapText(String text, int width) {
  final lines = <String>[];
  for (final paragraph in text.split('\n')) {
    final stripped = paragraph.trim();
    if (stripped.isEmpty) {
      if (lines.isNotEmpty) lines.add('');
      continue;
    }
    if (stripped.length <= width) {
      lines.add(stripped);
      continue;
    }

    var remaining = stripped;
    while (remaining.length > width) {
      var breakAt = remaining.lastIndexOf(' ', width);
      if (breakAt <= 0) breakAt = width;
      lines.add(remaining.substring(0, breakAt).trimRight());
      remaining = remaining.substring(breakAt).trimLeft();
    }
    if (remaining.isNotEmpty) lines.add(remaining);
  }
  return lines;
}

String _describeSkipped({
  required int upToDate,
  required int kind,
  required int nonHosted,
  required int nonstandard,
  required int unknown,
  int byBumpFilter = 0,
  int filteredCoordination = 0,
}) {
  final parts = <String>[];
  if (upToDate > 0) parts.add('$upToDate up-to-date');
  if (kind > 0) parts.add('$kind dev (--no-dev)');
  if (nonHosted > 0) parts.add('$nonHosted non-hosted');
  if (nonstandard > 0) parts.add('$nonstandard non-standard');
  if (unknown > 0) parts.add('$unknown transitive');
  if (byBumpFilter > 0) parts.add('$byBumpFilter above --bump');
  if (filteredCoordination > 0) {
    parts.add('$filteredCoordination filtered (--package)');
  }
  return parts.join(', ');
}

String _pluralize(String singular, int count, [String? plural]) {
  if (count == 1) return singular;
  return plural ?? '${singular}s';
}
