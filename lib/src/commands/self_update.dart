import 'package:pub_updater/pub_updater.dart';
import 'package:pubup/src/update_checker.dart';

/// Reinstalls pubup from pub.dev via `dart pub global activate`.
///
/// Returns `0` on success or when already up to date, `1` on failure.
Future<int> runSelfUpdate({
  required String currentVersion,
  required StringSink output,
  required StringSink errorOutput,
  required PubUpdater pubUpdater,
}) async {
  try {
    final latest = await pubUpdater.getLatestVersion(pubupPackageName);

    if (latest == currentVersion) {
      output.writeln(
        'pubup is already at the latest version ($currentVersion).',
      );
      return 0;
    }

    output.writeln('Updating pubup from $currentVersion to $latest...');

    final result = await pubUpdater.update(packageName: pubupPackageName);

    if (result.exitCode == 0) {
      output.writeln('pubup updated successfully to $latest.');
      return 0;
    }

    final failureOutput = (result.stderr as String).trim().isNotEmpty
        ? result.stderr as String
        : result.stdout as String;
    errorOutput.writeln(failureOutput.trim());
    return 1;
  } on Exception catch (e) {
    errorOutput.writeln('Failed to update pubup: $e');
    return 1;
  }
}
