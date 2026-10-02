import 'package:pub_semver/pub_semver.dart';
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

/// A declared dependency whose latest published version cannot be resolved
/// because another dependency or the SDK constrains it.
class HeldBackDependency {
  /// Creates a [HeldBackDependency].
  const HeldBackDependency({
    required this.name,
    required this.kind,
    required this.resolvableVersion,
    required this.latestVersion,
  });

  /// The package name.
  final String name;

  /// `"direct"` or `"dev"`.
  final String kind;

  /// The newest version pub can resolve today.
  final String resolvableVersion;

  /// The newest version published on pub.dev.
  final String latestVersion;
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

  /// Number of stable dependencies skipped because only a pre-release is
  /// newer (see `--prereleases`).
  int skippedPrerelease = 0;
}

/// Result of collecting update candidates for a single package.
class CollectionResult {
  /// Creates a [CollectionResult].
  CollectionResult({
    required this.candidates,
    required this.report,
    this.heldBack = const [],
  });

  /// Dependencies that should be updated.
  final List<CandidateUpdate> candidates;

  /// Classification counters.
  final CollectionReport report;

  /// Declared hosted dependencies whose latest version is not resolvable.
  final List<HeldBackDependency> heldBack;
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
/// [bumpLevel] caps how far constraints may move, and stable dependencies only
/// move to pre-releases when [allowPrereleases] is set. When the resolvable
/// version reported by `pub outdated` breaks either rule, pubup consults
/// [fetchVersions] for the highest qualifying version between the current
/// and the resolvable version. When [fetchVersions] is `null`, such
/// candidates are skipped.
///
/// Hosted dependencies whose latest version is newer than the resolvable one
/// are returned in [CollectionResult.heldBack].
Future<CollectionResult> collectCandidates({
  required List<OutdatedPackage> outdatedPackages,
  required PubspecDependencies deps,
  required bool includeDev,
  BumpLevel bumpLevel = BumpLevel.major,
  VersionsFetcher? fetchVersions,
  bool allowPrereleases = false,
}) async {
  final report = CollectionReport();
  final candidates = <CandidateUpdate>[];
  final heldBack = <HeldBackDependency>[];
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

    final held = _heldBack(row, allowPrereleases: allowPrereleases);
    if (held != null) heldBack.add(held);

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
      allowPrereleases: allowPrereleases,
    );

    if (targetVersion == null) {
      final exceedsBump = !versionFitsBound(
        level: bumpLevel,
        current: Version.parse(row.currentVersion),
        candidate: Version.parse(row.resolvableVersion),
      );
      if (exceedsBump) {
        report.skippedByBumpFilter++;
      } else {
        report.skippedPrerelease++;
      }
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

  return CollectionResult(
    candidates: candidates,
    report: report,
    heldBack: heldBack,
  );
}

HeldBackDependency? _heldBack(
  OutdatedPackage row, {
  required bool allowPrereleases,
}) {
  final latest = row.latestVersion;
  if (latest == null) return null;

  final Version currentV;
  final Version resolvableV;
  final Version latestV;
  try {
    currentV = Version.parse(row.currentVersion);
    resolvableV = Version.parse(row.resolvableVersion);
    latestV = Version.parse(latest);
  } on FormatException {
    return null;
  }

  if (latestV <= resolvableV) return null;
  if (!prereleaseAllowed(
    current: currentV,
    version: latestV,
    allowPrereleases: allowPrereleases,
  )) {
    return null;
  }

  return HeldBackDependency(
    name: row.package,
    kind: row.kind,
    resolvableVersion: row.resolvableVersion,
    latestVersion: latest,
  );
}
