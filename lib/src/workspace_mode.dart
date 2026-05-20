import 'dart:io';

import 'package:yaml/yaml.dart';

/// Returns `true` when [rootPubspec] declares a non-empty `workspace:` list.
///
/// Workspace roots use a single shared resolution graph; [pubup] applies a
/// coordinated update strategy in that case instead of per-package `pub add`.
bool isWorkspaceRoot(File rootPubspec) {
  if (!rootPubspec.existsSync()) return false;

  final content = rootPubspec.readAsStringSync();
  return isWorkspaceRootFromString(content);
}

/// Returns `true` when [content] declares a non-empty `workspace:` list.
bool isWorkspaceRootFromString(String content) {
  final dynamic yaml;
  try {
    yaml = loadYaml(content);
  } on Object {
    return false;
  }
  if (yaml is! YamlMap) return false;

  final workspace = yaml['workspace'];
  if (workspace is! YamlList || workspace.isEmpty) return false;

  return workspace.any((entry) => entry is String && entry.trim().isNotEmpty);
}
