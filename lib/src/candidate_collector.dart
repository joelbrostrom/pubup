import 'package:pubup/src/outdated_runner.dart';
import 'package:pubup/src/pubspec_parser.dart';
import 'package:pubup/src/version_resolver.dart';

/// A dependency that should be updated.
class CandidateUpdate {
  /// Creates a [CandidateUpdate].
  const CandidateUpdate({
    required this.name,
    required this.kind,
    required this.currentVersion,
    required this.targetVersion,
    required this.declaredConstraint,
  });

  /// The package name.
  final String name;

  /// `"direct"` or `"dev"`.
  final String kind;

  /// The currently resolved version.
  final String currentVersion;

  /// The version that pubup will write to `pubspec.yaml`.
  ///
  /// Without `--bump`, this is the latest resolvable version. With
  /// `--bump minor` or `--bump patch`, it may be a lower version chosen via
  /// the pub.dev version list.
  final String targetVersion;

  /// The constraint currently declared in `pubspec.yaml`.
  final String declaredConstraint;

  /// The target constraint that will be written, e.g. `"^1.2.3"`.
  String get targetConstraint => '^$targetVersion';
}

/// Counters tracking how dependencies were classified during collection.
class CollectionReport {
  /// Number of candidates that will be attempted.
  int attempted = 0;

  /// Number of dependencies already at the target constraint.
  int skippedUpToDate = 0;

  /// Number of dev dependencies skipped because `--no-dev` was used.
  int skippedKind = 0;

  /// Number of dependencies skipped due to non-hosted source.
  int skippedNonHosted = 0;

  /// Number of dependencies skipped due to non-standard constraints.
  int skippedNonstandard = 0;

  /// Number of dependencies skipped because they could not be classified.
  int skippedUnknown = 0;

  /// Number of dependencies skipped because the latest in-bound version is
  /// not above the current version (filtered by `--bump`).
  int skippedByBumpFilter = 0;
}

/// Result of collecting update candidates for a single package.
class CollectionResult {
  /// Creates a [CollectionResult].
  CollectionResult({
    required this.candidates,
    required this.report,
  });

  /// Dependencies that should be updated.
  final List<CandidateUpdate> candidates;

  /// Classification counters.
  final CollectionReport report;
}

/// Standard caret-version constraint pattern: `^1.2.3`, `1.2.3`,
/// `^1.2.3-beta`, `^1.2.3+build`.
final _standardConstraint =
    RegExp(r'^\^?\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-+]+)?$');

/// Collects update candidates from [outdatedPackages] by comparing against
/// the declared constraints in [deps].
///
/// Set [includeDev] to `false` to skip `dev_dependencies`.
///
/// [bumpLevel] caps how far constraints may move. With anything other than
/// [BumpLevel.major], pubup may consult [fetchVersions] to find the highest
/// in-bound version above the currently resolved version. When
/// [fetchVersions] is `null`, only the resolvable version reported by `pub
/// outdated` is considered; candidates whose resolvable version exceeds the
/// bound are skipped.
Future<CollectionResult> collectCandidates({
  required List<OutdatedPackage> outdatedPackages,
  required PubspecDependencies deps,
  required bool includeDev,
  BumpLevel bumpLevel = BumpLevel.major,
  VersionsFetcher? fetchVersions,
}) async {
  final report = CollectionReport();
  final candidates = <CandidateUpdate>[];
  final fetcher = fetchVersions ?? ((_) async => const <String>[]);

  for (final row in outdatedPackages) {
    if (row.kind != 'direct' && row.kind != 'dev') continue;

    if (row.kind == 'dev' && !includeDev) {
      report.skippedKind++;
      continue;
    }

    final sectionEntries = row.kind == 'direct' ? deps.direct : deps.dev;
    final entry = sectionEntries[row.package];

    if (entry == null) {
      report.skippedUnknown++;
      continue;
    }

    if (const {'path', 'git', 'sdk'}.contains(entry.source)) {
      report.skippedNonHosted++;
      continue;
    }

    if (entry.source == 'unknown') {
      report.skippedUnknown++;
      continue;
    }

    final declared = (entry.constraint ?? '').trim();
    if (declared.isEmpty || declared == 'any') {
      report.skippedNonstandard++;
      continue;
    }

    if (!_standardConstraint.hasMatch(declared)) {
      report.skippedNonstandard++;
      continue;
    }

    final targetVersion = await pickTargetVersion(
      level: bumpLevel,
      current: row.currentVersion,
      resolvable: row.resolvableVersion,
      packageName: row.package,
      fetchVersions: fetcher,
    );

    if (targetVersion == null) {
      report.skippedByBumpFilter++;
      continue;
    }

    final target = '^$targetVersion';
    if (declared == target) {
      report.skippedUpToDate++;
      continue;
    }

    report.attempted++;
    candidates.add(CandidateUpdate(
      name: row.package,
      kind: row.kind,
      currentVersion: row.currentVersion,
      targetVersion: targetVersion,
      declaredConstraint: declared,
    ));
  }

  return CollectionResult(candidates: candidates, report: report);
}
