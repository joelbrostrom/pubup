import 'dart:io';

import 'package:args/args.dart';
import 'package:pubup/src/pubspec_parser.dart';
import 'package:pubup/src/reporter.dart';
import 'package:pubup/src/updater.dart';
import 'package:pubup/src/workspace_discovery.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'dry-run',
      help: 'Preview changes without modifying pubspec.yaml files.',
      negatable: false,
    )
    ..addFlag(
      'dev',
      help: 'Include dev_dependencies.',
      defaultsTo: true,
    )
    ..addMultiOption(
      'package',
      help: 'Limit updates to specific workspace package(s). '
          'Matches path, folder name, "root", or ".". Repeatable.',
    )
    ..addOption(
      'root',
      help: 'Project root directory.',
      defaultsTo: '.',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help message.',
      negatable: false,
    );

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln();
    stderr.writeln('Usage: pubup [options]');
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (results.flag('help')) {
    stdout.writeln('Update pubspec.yaml dependency constraints to the latest '
        'resolvable versions.');
    stdout.writeln();
    stdout.writeln('Usage: pubup [options]');
    stdout.writeln();
    stdout.writeln(parser.usage);
    exit(0);
  }

  final dryRun = results.flag('dry-run');
  final includeDev = results.flag('dev');
  final packageFilters = results.multiOption('package');
  final repoRoot = Directory(results.option('root')!).absolute;

  List<Directory> targets;
  try {
    targets = discoverWorkspaceDirs(repoRoot);
  } on FileSystemException catch (e) {
    stderr.writeln('Error: ${e.message} (${e.path})');
    exit(1);
  }

  targets = filterTargets(targets, packageFilters, repoRoot);

  if (targets.isEmpty) {
    stderr.writeln('No matching workspace packages found for --package '
        'filters.');
    exit(1);
  }

  final reports = <PackageReport>[];

  for (final target in targets) {
    final pubspec = File('${target.path}/pubspec.yaml');
    final command = isFlutterPackage(pubspec) ? 'flutter' : 'dart';
    final isRoot = target.path == repoRoot.path;
    final rel = isRoot ? '.' : target.path.substring(repoRoot.path.length + 1);

    stdout.writeln();
    stdout.writeln('Package: $rel ($command pub)');

    try {
      final report = await runUpdatesForPackage(
        packageDir: target,
        command: command,
        includeDev: includeDev,
        dryRun: dryRun,
        output: stdout,
        errorOutput: stderr,
      );
      reports.add(report);
    } on Exception catch (e) {
      final failedReport = PackageReport(
        packageDir: target.path,
        command: command,
      )..failed = 1;
      failedReport.failures.add(e.toString());
      reports.add(failedReport);
      stderr.writeln('  ! Failed package scan: $e');
    }
  }

  final exitCode = printReport(reports, dryRun: dryRun, output: stdout);
  exit(exitCode);
}
