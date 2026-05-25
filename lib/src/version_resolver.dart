import 'package:pub_semver/pub_semver.dart';

/// How far constraints may move during an update.
///
/// Use [BumpLevel.minor] or [BumpLevel.patch] to avoid major-version bumps
/// that often introduce breaking changes.
enum BumpLevel {
  /// Allow any update, including major-version bumps. Default behaviour.
  major,

  /// Only allow updates that keep the leading version segment unchanged
  /// (e.g. `1.2.3` stays in `1.x.y`, `0.1.2` stays in `0.x.y`).
  minor,

  /// Only allow updates that keep the leading two version segments unchanged
  /// (e.g. `1.2.3` stays in `1.2.x`, `0.1.2` stays in `0.1.x`).
  patch,
}

/// Parses [BumpLevel] from a CLI string. Returns [BumpLevel.major] for
/// unknown values so callers can rely on a non-null result; CLI parsing
/// should reject unknown values up front.
BumpLevel bumpLevelFromString(String value) {
  switch (value) {
    case 'minor':
      return BumpLevel.minor;
    case 'patch':
      return BumpLevel.patch;
    case 'major':
    default:
      return BumpLevel.major;
  }
}

/// Fetches all published versions of a package from pub.dev.
///
/// Implementations should return version strings parsable by `pub_semver`.
typedef VersionsFetcher = Future<List<String>> Function(String packageName);

/// Returns `true` if [candidate] is within the [level] bound relative to
/// [current].
///
/// `BumpLevel.major` always returns `true`. `BumpLevel.minor` requires the
/// leading segment to match. `BumpLevel.patch` requires the leading two
/// segments to match.
bool versionFitsBound({
  required BumpLevel level,
  required Version current,
  required Version candidate,
}) {
  switch (level) {
    case BumpLevel.major:
      return true;
    case BumpLevel.minor:
      return candidate.major == current.major;
    case BumpLevel.patch:
      return candidate.major == current.major &&
          candidate.minor == current.minor;
  }
}

/// Picks the target version pubup should bump to.
///
/// Returns `null` to indicate the candidate should be skipped (no version
/// within the bump bound exists above [current]).
///
/// Strategy:
///
/// 1. If [level] is [BumpLevel.major], return [resolvable] (no filtering).
/// 2. If [resolvable] already fits the bound, return it (no network call).
/// 3. Otherwise call [fetchVersions], filter to non-prerelease versions
///    above [current] that fit the bound, return the highest, or `null`.
///
/// Pre-releases on pub.dev are excluded unless [current] itself is a
/// pre-release matching that channel.
Future<String?> pickTargetVersion({
  required BumpLevel level,
  required String current,
  required String resolvable,
  required String packageName,
  required VersionsFetcher fetchVersions,
}) async {
  final currentV = Version.parse(current);
  final resolvableV = Version.parse(resolvable);

  if (level == BumpLevel.major) {
    return resolvable;
  }

  if (versionFitsBound(
    level: level,
    current: currentV,
    candidate: resolvableV,
  )) {
    return resolvable;
  }

  final List<String> rawVersions;
  try {
    rawVersions = await fetchVersions(packageName);
  } on Object {
    return null;
  }

  Version? best;
  for (final raw in rawVersions) {
    final Version v;
    try {
      v = Version.parse(raw);
    } on FormatException {
      continue;
    }

    if (v.isPreRelease && !currentV.isPreRelease) continue;
    if (v <= currentV) continue;
    if (!versionFitsBound(level: level, current: currentV, candidate: v)) {
      continue;
    }

    if (best == null || v > best) best = v;
  }

  return best?.toString();
}
