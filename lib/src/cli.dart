import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;
import 'package:pub_updater/pub_updater.dart';
import 'package:pubup/src/commands/self_update.dart';
import 'package:pubup/src/pubdev_client.dart';
import 'package:pubup/src/pubspec_parser.dart';
import 'package:pubup/src/reporter.dart';
import 'package:pubup/src/sdk_resolver.dart';
import 'package:pubup/src/status_line.dart';
import 'package:pubup/src/update_checker.dart';
import 'package:pubup/src/updater.dart';
import 'package:pubup/src/version.dart';
import 'package:pubup/src/version_resolver.dart';
import 'package:pubup/src/workspace_discovery.dart';
import 'package:pubup/src/workspace_mode.dart';
import 'package:pubup/src/workspace_updater.dart';

/// Runs the `pubup` command line with [arguments] and returns its exit code.
///
/// [output] and [errorOutput] default to [stdout] and [stderr]. [pubUpdater]
/// serves `pubup update` and the update notice, [httpClient] the pub.dev
/// version lookups for `--bump`. [environment] and [isInteractive] default
/// to the process environment and stderr's terminal status.
Future<int> runCli(
  List<String> arguments, {
  StringSink? output,
  StringSink? errorOutput,
  PubUpdater? pubUpdater,
  http.Client? httpClient,
  Map<String, String>? environment,
  bool? isInteractive,
}) async {
  final out = output ?? stdout;
  final err = errorOutput ?? stderr;
  final updater = pubUpdater ?? PubUpdater();
  final parser = _buildParser();

  final ArgResults results;
  try {
    results = parser.parse(arguments);
  } on FormatException catch (e) {
    err
      ..writeln('Error: ${e.message}')
      ..writeln()
      ..writeln('Usage: pubup [options]')
      ..writeln('       pubup update')
      ..writeln()
      ..writeln(parser.usage);
    return 64;
  }

  if (results.flag('help')) {
    out
      ..writeln(
        'Update pubspec.yaml dependency constraints to the latest '
        'resolvable versions.',
      )
      ..writeln()
      ..writeln('Usage: pubup [options]')
      ..writeln('       pubup update')
      ..writeln()
      ..writeln(parser.usage);
    return 0;
  }

  if (results.flag('version')) {
    out.writeln('pubup $packageVersion');
    return 0;
  }

  final updateResults = results.command;
  if (updateResults?.name == 'update') {
    if (updateResults!.flag('help')) {
      out
        ..writeln('Reinstall pubup from pub.dev.')
        ..writeln()
        ..writeln('Usage: pubup update');
      return 0;
    }

    return runSelfUpdate(
      currentVersion: packageVersion,
      output: out,
      errorOutput: err,
      pubUpdater: updater,
    );
  }

  final pubDevClient = PubDevClient(httpClient: httpClient);
  final statusLine = StatusLine(out: err, environment: environment);

  try {
    return await _runUpdates(
      results,
      output: out,
      errorOutput: err,
      statusLine: statusLine,
      fetchVersions: pubDevClient.getVersions,
    );
  } finally {
    statusLine.clear();
    pubDevClient.close();
    await checkForUpdate(
      currentVersion: packageVersion,
      errorOutput: err,
      pubUpdater: updater,
      environment: environment,
      isInteractive: isInteractive,
    );
  }
}

ArgParser _buildParser() => ArgParser()
  ..addFlag(
    'dry-run',
    help: 'Preview changes without modifying pubspec.yaml files.',
    negatable: false,
  )
  ..addFlag('dev', help: 'Include dev_dependencies.', defaultsTo: true)
  ..addMultiOption(
    'package',
    help: 'Limit updates to specific workspace package(s). '
        'Matches path, folder name, "root", or ".". Repeatable.',
  )
  ..addOption('root', help: 'Project root directory.', defaultsTo: '.')
  ..addOption(
    'bump',
    help: 'Limit how far constraints may move. '
        'Use "minor" or "patch" to avoid breaking changes during an update.',
    allowed: ['major', 'minor', 'patch'],
    allowedHelp: {
      'major': 'Allow any update, including major-version bumps (default).',
      'minor': 'Only allow updates within the current major version.',
      'patch': 'Only allow updates within the current major.minor.',
    },
    defaultsTo: 'major',
  )
  ..addFlag(
    'prereleases',
    help: 'Allow stable dependencies to move to pre-release versions '
        '(e.g. 2.0.0-rc.1). Off by default.',
    negatable: false,
  )
  ..addOption(
    'sdk',
    help: 'Flutter or Dart SDK to run pub with. Defaults to the FVM pin in '
        '.fvmrc, then flutter/dart on PATH.',
    valueHelp: 'path',
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
    'update',
    ArgParser()..addFlag('help', abbr: 'h', negatable: false),
  );

Future<int> _runUpdates(
  ArgResults results, {
  required StringSink output,
  required StringSink errorOutput,
  required StatusLine statusLine,
  required VersionsFetcher fetchVersions,
}) async {
  final dryRun = results.flag('dry-run');
  final includeDev = results.flag('dev');
  final repoRoot = Directory(results.option('root')!).absolute;
  final bumpLevel = bumpLevelFromString(results.option('bump')!);
  final allowPrereleases = results.flag('prereleases');

  List<Directory> targets;
  try {
    targets = discoverWorkspaceDirs(repoRoot);
  } on FileSystemException catch (e) {
    errorOutput.writeln('Error: ${e.message} (${e.path})');
    return 1;
  }

  targets = filterTargets(targets, results.multiOption('package'), repoRoot);
  if (targets.isEmpty) {
    errorOutput.writeln(
      'No matching workspace packages found for --package '
      'filters.',
    );
    return 1;
  }

  final PubSdk sdk;
  try {
    sdk = resolvePubSdk(
      repoRoot: repoRoot,
      sdkPath: results.option('sdk'),
      warnings: errorOutput,
    );
  } on SdkResolutionException catch (e) {
    errorOutput.writeln('Error: ${e.message}');
    return 1;
  }

  final rootPubspec = File('${repoRoot.path}/pubspec.yaml');
  final rootCommand = isFlutterPackage(rootPubspec) ? 'flutter' : 'dart';

  statusLine.update('Checking SDK version');
  final sdkLine = await describeSdk(sdk: sdk, command: rootCommand);
  statusLine.update(null);

  if (isWorkspaceRoot(rootPubspec)) {
    output
      ..writeln()
      ..writeln(
        'Workspace: ${directoryDisplayName(repoRoot)} ($rootCommand pub)',
      )
      ..writeln(sdkLine)
      ..writeln();

    final workspaceReport = await runUpdatesForWorkspace(
      repoRoot: repoRoot,
      scanTargets: targets,
      allWorkspaceDirs: discoverWorkspaceDirs(repoRoot),
      includeDev: includeDev,
      dryRun: dryRun,
      output: output,
      errorOutput: errorOutput,
      bumpLevel: bumpLevel,
      allowPrereleases: allowPrereleases,
      sdk: sdk,
      fetchVersions: fetchVersions,
      onStatus: statusLine.update,
    );

    return printWorkspaceReport(
      workspaceReport,
      dryRun: dryRun,
      output: output,
    );
  }

  final reports = <PackageReport>[];

  output
    ..writeln()
    ..writeln(sdkLine);

  for (final target in targets) {
    final pubspec = File('${target.path}/pubspec.yaml');
    final command = isFlutterPackage(pubspec) ? 'flutter' : 'dart';

    output
      ..writeln()
      ..writeln(
        'Package: ${workspaceRelativePath(target, repoRoot)} ($command pub)',
      )
      ..writeln();

    try {
      final report = await runUpdatesForPackage(
        packageDir: target,
        command: command,
        includeDev: includeDev,
        dryRun: dryRun,
        output: output,
        errorOutput: errorOutput,
        bumpLevel: bumpLevel,
        allowPrereleases: allowPrereleases,
        executable: sdk.executable(command),
        fetchVersions: fetchVersions,
        onStatus: statusLine.update,
      );
      reports.add(report);
    } on Exception catch (e) {
      statusLine.clear();
      final failedReport = PackageReport(
        packageDir: target.path,
        command: command,
      )..failed = 1;
      failedReport.failures.add(e.toString());
      reports.add(failedReport);
      errorOutput.writeln('  ! Failed package scan: $e');
    }
  }

  return printReport(reports, dryRun: dryRun, output: output);
}
