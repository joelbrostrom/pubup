// ignore_for_file: avoid_print

/// Example: using pubup programmatically.
///
/// This example demonstrates how to use the library API to discover workspace
/// packages, check for outdated dependencies, and collect update candidates
/// — all without modifying any files (equivalent to `--dry-run`).
///
/// Run from a Dart or Flutter project root:
///
/// ```bash
/// dart run example/example.dart
/// ```
library;

import 'dart:io';

import 'package:pubup/pubup.dart';

Future<void> main() async {
  final repoRoot = Directory.current;

  // 1. Discover workspace packages.
  final targets = discoverWorkspaceDirs(repoRoot);
  print('Found ${targets.length} package(s) in workspace.\n');

  // 2. For each package, collect update candidates.
  for (final target in targets) {
    final pubspec = File('${target.path}/pubspec.yaml');
    final command = isFlutterPackage(pubspec) ? 'flutter' : 'dart';
    final rel = target.path == repoRoot.path
        ? '.'
        : target.path.substring(repoRoot.path.length + 1);

    print('Package: $rel ($command pub)');

    final outdated = await getOutdatedPackages(command, target);
    final deps = parseDependencyEntries(pubspec);
    final result = await collectCandidates(
      outdatedPackages: outdated,
      deps: deps,
      includeDev: true,
    );

    if (result.candidates.isEmpty) {
      print('  All dependencies are up to date.\n');
      continue;
    }

    for (final c in result.candidates) {
      print('  ${c.kind.padRight(6)} ${c.name}: '
          '${c.declaredConstraint} -> ${c.targetConstraint}');
    }
    print('');
  }
}
