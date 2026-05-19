import 'dart:async';
import 'dart:io';

import 'package:pub_updater/pub_updater.dart';

/// The pub.dev package name used for version checks and self-update.
const pubupPackageName = 'pubup';

/// Environment variable that disables the once-per-day update notice when set
/// to any value other than `0` or `false`.
const disableUpdateCheckEnv = 'PUBUP_DISABLE_UPDATE_CHECK';

const _cacheFileName = 'last_update_check';

/// Returns whether the update check should be skipped for [environment].
///
/// When [isInteractive] is `false` (e.g. stderr is not attached to a TTY),
/// the check is skipped automatically. This keeps automation contexts like
/// coding agents, CI runners, and shell pipelines quiet without requiring
/// callers to set [disableUpdateCheckEnv] explicitly.
bool isUpdateCheckDisabled(
  Map<String, String> environment, {
  bool isInteractive = true,
}) {
  if (!isInteractive) return true;
  if (environment['CI'] == 'true') return true;

  final disableValue = environment[disableUpdateCheckEnv];
  if (disableValue == null) return false;
  if (disableValue.isEmpty) return true;

  return disableValue != '0' && disableValue.toLowerCase() != 'false';
}

/// Resolves the directory used to cache the last pub.dev version check.
///
/// Uses [environment]'s `PUB_CACHE` when set, otherwise `$HOME/.pub-cache/pubup`.
Directory resolveUpdateCacheDir(Map<String, String> environment) {
  final home = environment['HOME'] ?? Platform.environment['HOME'] ?? '';
  final pubCache = environment['PUB_CACHE'] ?? '$home/.pub-cache';
  return Directory('$pubCache/pubup');
}

/// Checks pub.dev for a newer pubup release and prints a one-line notice on
/// [errorOutput] when [currentVersion] is behind.
///
/// The check runs at most once per [cacheDuration] (default 24 hours). Skipped
/// when [environment] has `CI=true`, [disableUpdateCheckEnv] is set, or
/// [isInteractive] is `false` (defaults to `stderr.hasTerminal`, so the notice
/// is automatically suppressed when stderr is piped or being captured by an
/// agent / automation).
///
/// Network errors and timeouts are swallowed so offline users are not blocked.
Future<void> checkForUpdate({
  required String currentVersion,
  required StringSink errorOutput,
  required PubUpdater pubUpdater,
  Directory? cacheDir,
  Map<String, String>? environment,
  bool? isInteractive,
  Duration cacheDuration = const Duration(hours: 24),
  Duration timeout = const Duration(seconds: 2),
}) async {
  final env = environment ?? Platform.environment;
  final interactive = isInteractive ?? stderr.hasTerminal;
  if (isUpdateCheckDisabled(env, isInteractive: interactive)) return;

  final dir = cacheDir ?? resolveUpdateCacheDir(env);
  final cacheFile = File('${dir.path}/$_cacheFileName');

  if (_isCacheFresh(cacheFile, cacheDuration)) return;

  try {
    final latest =
        await pubUpdater.getLatestVersion(pubupPackageName).timeout(timeout);

    await _touchCacheFile(cacheFile);

    if (latest != currentVersion) {
      errorOutput.writeln(
        'pubup $latest is available (you have $currentVersion). '
        'Run `pubup update` to upgrade.',
      );
    }
  } on Object {
    await _touchCacheFile(cacheFile);
  }
}

bool _isCacheFresh(File cacheFile, Duration cacheDuration) {
  if (!cacheFile.existsSync()) return false;
  final modified = cacheFile.lastModifiedSync();
  return DateTime.now().difference(modified) < cacheDuration;
}

Future<void> _touchCacheFile(File cacheFile) async {
  await cacheFile.parent.create(recursive: true);
  await cacheFile.writeAsString(DateTime.now().toIso8601String());
}
