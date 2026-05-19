import 'dart:convert';
import 'dart:io';

/// A single row from the `pub outdated --json` output.
class OutdatedPackage {
  /// Creates an [OutdatedPackage].
  const OutdatedPackage({
    required this.package,
    required this.kind,
    required this.currentVersion,
    required this.resolvableVersion,
  });

  /// Parses an [OutdatedPackage] from a JSON map.
  ///
  /// Returns `null` if required fields are missing.
  static OutdatedPackage? fromJson(Map<String, dynamic> json) {
    final package = json['package'] as String?;
    final kind = json['kind'] as String?;
    final current =
        (json['current'] as Map<String, dynamic>?)?['version'] as String?;
    final resolvable =
        (json['resolvable'] as Map<String, dynamic>?)?['version'] as String?;

    if (package == null ||
        kind == null ||
        current == null ||
        resolvable == null) {
      return null;
    }

    return OutdatedPackage(
      package: package,
      kind: kind,
      currentVersion: current,
      resolvableVersion: resolvable,
    );
  }

  /// The package name.
  final String package;

  /// The dependency kind: `"direct"`, `"dev"`, or `"transitive"`.
  final String kind;

  /// The currently resolved version in `pubspec.lock`.
  final String currentVersion;

  /// The latest version resolvable under current SDK and dependency constraints.
  final String resolvableVersion;
}

/// Runs `pub outdated --json --show-all` in [packageDir] and returns parsed
/// package rows.
///
/// Uses [command] as the executable (`"dart"` or `"flutter"`).
///
/// Throws a [ProcessException] if the command fails.
Future<List<OutdatedPackage>> getOutdatedPackages(
  String command,
  Directory packageDir,
) async {
  final result = await Process.run(
    command,
    ['pub', 'outdated', '--json', '--show-all'],
    workingDirectory: packageDir.path,
  );

  if (result.exitCode != 0) {
    final output = (result.stderr as String).trim().isNotEmpty
        ? result.stderr as String
        : result.stdout as String;
    throw ProcessException(
      command,
      ['pub', 'outdated', '--json', '--show-all'],
      output.trim(),
      result.exitCode,
    );
  }

  return parseOutdatedJson(result.stdout as String);
}

/// Parses the stdout of `pub outdated --json --show-all` into a list of
/// [OutdatedPackage]s.
///
/// `flutter pub` may print extra content alongside the JSON — most commonly
/// the "A new version of Flutter is available" banner that wraps text in a
/// box drawn with `┌─┐│└─┘`. This function tolerates such noise by extracting
/// the JSON object between the first `{` and the matching last `}` in
/// [stdout].
///
/// Throws a [FormatException] if no JSON object is found.
List<OutdatedPackage> parseOutdatedJson(String stdout) {
  final start = stdout.indexOf('{');
  final end = stdout.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw FormatException(
      'Could not find a JSON object in pub outdated output.',
      stdout,
    );
  }

  final jsonStr = stdout.substring(start, end + 1);
  final json = jsonDecode(jsonStr) as Map<String, dynamic>;
  final packages = json['packages'] as List<dynamic>? ?? [];

  return packages
      .whereType<Map<String, dynamic>>()
      .map(OutdatedPackage.fromJson)
      .whereType<OutdatedPackage>()
      .toList();
}
