import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:pubup/src/commands/self_update.dart';
import 'package:pubup/src/update_checker.dart';
import 'package:test/test.dart';

class _MockPubUpdater extends Mock implements PubUpdater {}

void main() {
  late _MockPubUpdater pubUpdater;
  late StringBuffer output;
  late StringBuffer errorOutput;

  setUp(() {
    pubUpdater = _MockPubUpdater();
    output = StringBuffer();
    errorOutput = StringBuffer();
  });

  group('runSelfUpdate', () {
    test('returns 0 when already at latest version', () async {
      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenAnswer((_) async => '0.2.0');

      final exitCode = await runSelfUpdate(
        currentVersion: '0.2.0',
        output: output,
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
      );

      expect(exitCode, 0);
      expect(output.toString(), contains('already at the latest version'));
      verifyNever(
        () => pubUpdater.update(packageName: any(named: 'packageName')),
      );
    });

    test('returns 0 when update succeeds', () async {
      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenAnswer((_) async => '0.3.0');
      when(() => pubUpdater.update(packageName: pubupPackageName)).thenAnswer(
        (_) async => ProcessResult(
          0,
          0,
          'Activated pubup 0.3.0.',
          '',
        ),
      );

      final exitCode = await runSelfUpdate(
        currentVersion: '0.2.0',
        output: output,
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
      );

      expect(exitCode, 0);
      expect(output.toString(), contains('Updating pubup'));
      expect(output.toString(), contains('updated successfully'));
      verify(() => pubUpdater.update(packageName: pubupPackageName)).called(1);
    });

    test('returns 1 when update command fails with stderr', () async {
      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenAnswer((_) async => '0.3.0');
      when(() => pubUpdater.update(packageName: pubupPackageName)).thenAnswer(
        (_) async => ProcessResult(
          0,
          1,
          '',
          'Activation failed.',
        ),
      );

      final exitCode = await runSelfUpdate(
        currentVersion: '0.2.0',
        output: output,
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
      );

      expect(exitCode, 1);
      expect(errorOutput.toString(), contains('Activation failed'));
    });

    test('returns 1 when update fails with stdout only', () async {
      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenAnswer((_) async => '0.3.0');
      when(() => pubUpdater.update(packageName: pubupPackageName)).thenAnswer(
        (_) async => ProcessResult(
          0,
          1,
          'stdout failure',
          '',
        ),
      );

      final exitCode = await runSelfUpdate(
        currentVersion: '0.2.0',
        output: output,
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
      );

      expect(exitCode, 1);
      expect(errorOutput.toString(), contains('stdout failure'));
    });

    test('returns 1 when getLatestVersion throws', () async {
      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenThrow(Exception('network error'));

      final exitCode = await runSelfUpdate(
        currentVersion: '0.2.0',
        output: output,
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
      );

      expect(exitCode, 1);
      expect(errorOutput.toString(), contains('Failed to update pubup'));
    });
  });
}
