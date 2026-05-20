import 'dart:io';

import 'package:args/args.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:pubup/src/commands/self_update.dart';
import 'package:pubup/src/pubspec_parser.dart';
import 'package:pubup/src/reporter.dart';
import 'package:pubup/src/update_checker.dart';
import 'package:pubup/src/updater.dart';
import 'package:pubup/src/version.dart';
import 'package:pubup/src/workspace_discovery.dart';
import 'package:pubup/src/workspace_mode.dart';
import 'package:pubup/src/workspace_updater.dart';

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
      'version',
      abbr: 'V',
      help: 'Print the current version.',
      negatable: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help message.',
      negatable: false,
    )
    ..addCommand(
        'update', ArgParser()..addFlag('help', abbr: 'h', negatable: false));

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    stderr.writeln();
    stderr.writeln('Usage: pubup [options]');
    stderr.writeln('       pubup update');
    stderr.writeln();
    stderr.writeln(parser.usage);
    exit(64);
  }

  if (results.flag('help')) {
    _printHelp(parser);
    exit(0);
  }

  if (results.flag('version')) {
    stdout.writeln('pubup $packageVersion');
    exit(0);
  }

  final updateResults = results.command;
  if (updateResults?.name == 'update') {
    if (updateResults!.flag('help')) {
      stdout.writeln('Reinstall pubup from pub.dev.');
      stdout.writeln();
      stdout.writeln('Usage: pubup update');
      exit(0);
    }

    final exitCode = await runSelfUpdate(
      currentVersion: packageVersion,
      output: stdout,
      errorOutput: stderr,
      pubUpdater: PubUpdater(),
    );
    exit(exitCode);
  }

  final dryRun = results.flag('dry-run');
  final includeDev = results.flag('dev');
  final packageFilters = results.multiOption('package');
  final repoRoot = Directory(results.option('root')!).absolute;

  var exitCode = 0;

  try {
    List<Directory> targets;
    try {
      targets = discoverWorkspaceDirs(repoRoot);
    } on FileSystemException catch (e) {
      stderr.writeln('Error: ${e.message} (${e.path})');
      exitCode = 1;
      return;
    }

    targets = filterTargets(targets, packageFilters, repoRoot);

    if (targets.isEmpty) {
      stderr.writeln('No matching workspace packages found for --package '
          'filters.');
      exitCode = 1;
      return;
    }

    final rootPubspec = File('${repoRoot.path}/pubspec.yaml');

    if (isWorkspaceRoot(rootPubspec)) {
      final pubCmd = isFlutterPackage(rootPubspec) ? 'flutter' : 'dart';
      stdout.writeln();
      stdout.writeln('Workspace: ${_basename(repoRoot.path)} ($pubCmd pub)');
      stdout.writeln();

      final workspaceReport = await runUpdatesForWorkspace(
        repoRoot: repoRoot,
        scanTargets: targets,
        allWorkspaceDirs: discoverWorkspaceDirs(repoRoot),
        includeDev: includeDev,
        dryRun: dryRun,
        output: stdout,
        errorOutput: stderr,
      );

      exitCode = printWorkspaceReport(
        workspaceReport,
        dryRun: dryRun,
        output: stdout,
      );
    } else {
      final reports = <PackageReport>[];

      for (final target in targets) {
        final pubspec = File('${target.path}/pubspec.yaml');
        final command = isFlutterPackage(pubspec) ? 'flutter' : 'dart';
        final isRoot = target.path == repoRoot.path;
        final rel =
            isRoot ? '.' : target.path.substring(repoRoot.path.length + 1);

        stdout.writeln();
        stdout.writeln('Package: $rel ($command pub)');
        stdout.writeln();

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

      exitCode = printReport(reports, dryRun: dryRun, output: stdout);
    }
  } finally {
    await checkForUpdate(
      currentVersion: packageVersion,
      errorOutput: stderr,
      pubUpdater: PubUpdater(),
    );
  }

  exit(exitCode);
}

String _basename(String path) {
  final sep = path.lastIndexOf('/');
  final sepWin = path.lastIndexOf(r'\');
  final last = sep > sepWin ? sep : sepWin;
  final name = last < 0 ? path : path.substring(last + 1);
  return name.isEmpty ? path : name;
}

void _printHelp(ArgParser parser) {
  stdout.writeln('Update pubspec.yaml dependency constraints to the latest '
      'resolvable versions.');
  stdout.writeln();
  stdout.writeln('Usage: pubup [options]');
  stdout.writeln('       pubup update');
  stdout.writeln();
  stdout.writeln(parser.usage);
}
