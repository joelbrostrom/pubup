import 'dart:io';

import 'package:yaml/yaml.dart';

/// Discovers all package directories in a Dart/Flutter workspace.
///
/// Reads the root `pubspec.yaml` and extracts entries from the `workspace:`
/// section. If no workspace section exists, returns only the [repoRoot].
///
/// Each returned [Directory] is guaranteed to contain a `pubspec.yaml` file.
List<Directory> discoverWorkspaceDirs(Directory repoRoot) {
  final rootPubspec = File('${repoRoot.path}/pubspec.yaml');
  if (!rootPubspec.existsSync()) {
    throw FileSystemException(
      'Missing root pubspec.yaml',
      rootPubspec.path,
    );
  }

  final content = rootPubspec.readAsStringSync();
  final yaml = loadYaml(content);

  final dirs = <Directory>[repoRoot];

  if (yaml is! YamlMap) return dirs;

  final workspace = yaml['workspace'];
  if (workspace is! YamlList) return dirs;

  for (final entry in workspace) {
    if (entry is! String) continue;
    final packageDir = Directory('${repoRoot.path}/$entry');
    final pubspec = File('${packageDir.path}/pubspec.yaml');
    if (pubspec.existsSync()) {
      dirs.add(packageDir);
    }
  }

  return dirs;
}

/// Filters a list of workspace [targets] to only those matching [selectors].
///
/// Each selector is matched against the directory name, the relative path from
/// [repoRoot], or the special values `"root"` and `"."` for the root package.
///
/// Returns all [targets] if [selectors] is empty.
List<Directory> filterTargets(
  List<Directory> targets,
  List<String> selectors,
  Directory repoRoot,
) {
  if (selectors.isEmpty) return targets;

  final wanted =
      selectors.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet();

  return targets.where((target) {
    final isRoot = target.path == repoRoot.path;
    final rel = isRoot ? '.' : _relativePath(target.path, repoRoot.path);
    final names = {rel, _basename(target.path)};
    if (isRoot) names.addAll(['root', '.']);
    return names.intersection(wanted).isNotEmpty;
  }).toList();
}

String _relativePath(String child, String parent) {
  final normalized =
      child.startsWith(parent) ? child.substring(parent.length) : child;
  final trimmed = normalized.startsWith('/') || normalized.startsWith(r'\')
      ? normalized.substring(1)
      : normalized;
  return trimmed.isEmpty ? '.' : trimmed;
}

String _basename(String path) {
  final sep = path.lastIndexOf('/');
  final sepWin = path.lastIndexOf(r'\');
  final last = sep > sepWin ? sep : sepWin;
  return last < 0 ? path : path.substring(last + 1);
}
