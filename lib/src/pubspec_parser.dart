import 'dart:io';

import 'package:yaml/yaml.dart';

/// Describes a single dependency entry parsed from a `pubspec.yaml` file.
class DependencyEntry {
  /// Creates a [DependencyEntry].
  const DependencyEntry({
    required this.source,
    this.constraint,
  });

  /// The dependency source type: `"hosted"`, `"path"`, `"git"`, `"sdk"`,
  /// or `"unknown"`.
  final String source;

  /// The declared version constraint string, e.g. `"^1.2.3"` or `"any"`.
  ///
  /// May be `null` for dependencies that use non-scalar forms without an
  /// explicit version field.
  final String? constraint;
}

/// Parsed dependency entries for a single `pubspec.yaml` file.
class PubspecDependencies {
  /// Creates a [PubspecDependencies].
  const PubspecDependencies({
    required this.direct,
    required this.dev,
  });

  /// Direct dependencies from the `dependencies:` section.
  final Map<String, DependencyEntry> direct;

  /// Dev dependencies from the `dev_dependencies:` section.
  final Map<String, DependencyEntry> dev;
}

/// Parses dependency entries from a `pubspec.yaml` file at [pubspecPath].
///
/// Uses the `yaml` package for robust parsing. Each dependency is classified
/// by its source type and its declared version constraint is extracted.
PubspecDependencies parseDependencyEntries(File pubspecPath) {
  final content = pubspecPath.readAsStringSync();
  return parseDependencyEntriesFromString(content);
}

/// Parses dependency entries from a YAML [content] string.
///
/// This is the testable core of [parseDependencyEntries].
PubspecDependencies parseDependencyEntriesFromString(String content) {
  final yaml = loadYaml(content);
  if (yaml is! YamlMap) {
    return const PubspecDependencies(direct: {}, dev: {});
  }

  return PubspecDependencies(
    direct: _parseSection(yaml['dependencies']),
    dev: _parseSection(yaml['dev_dependencies']),
  );
}

/// Returns `true` if the pubspec at [pubspecPath] depends on the Flutter SDK.
///
/// This is used to decide whether to invoke `flutter pub` or `dart pub`.
bool isFlutterPackage(File pubspecPath) {
  final content = pubspecPath.readAsStringSync();
  return isFlutterPackageFromString(content);
}

/// Returns `true` if the YAML [content] declares a Flutter SDK dependency.
///
/// This is the testable core of [isFlutterPackage].
bool isFlutterPackageFromString(String content) {
  final yaml = loadYaml(content);
  if (yaml is! YamlMap) return false;

  final deps = yaml['dependencies'];
  if (deps is! YamlMap) return false;

  final flutter = deps['flutter'];
  if (flutter is! YamlMap) return false;

  return flutter['sdk'] == 'flutter';
}

Map<String, DependencyEntry> _parseSection(dynamic section) {
  if (section is! YamlMap) return {};

  final entries = <String, DependencyEntry>{};

  for (final key in section.keys) {
    final name = key.toString();
    final value = section[key];

    if (value == null) {
      entries[name] = const DependencyEntry(
        source: 'hosted',
        constraint: 'any',
      );
      continue;
    }

    if (value is String) {
      entries[name] = DependencyEntry(source: 'hosted', constraint: value);
      continue;
    }

    if (value is! YamlMap) {
      entries[name] = const DependencyEntry(source: 'unknown');
      continue;
    }

    if (value.containsKey('path')) {
      entries[name] = const DependencyEntry(source: 'path');
    } else if (value.containsKey('git')) {
      entries[name] = const DependencyEntry(source: 'git');
    } else if (value.containsKey('sdk')) {
      entries[name] = DependencyEntry(
        source: 'sdk',
        constraint: value['sdk']?.toString(),
      );
    } else if (value.containsKey('hosted')) {
      entries[name] = DependencyEntry(
        source: 'hosted',
        constraint: value['version']?.toString(),
      );
    } else if (value.containsKey('version')) {
      entries[name] = DependencyEntry(
        source: 'hosted',
        constraint: value['version']?.toString(),
      );
    } else {
      entries[name] = const DependencyEntry(source: 'unknown');
    }
  }

  return entries;
}
