import 'dart:async';
import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:pub_updater/pub_updater.dart';
import 'package:pubup/src/update_checker.dart';
import 'package:test/test.dart';

class _MockPubUpdater extends Mock implements PubUpdater {}

void main() {
  late _MockPubUpdater pubUpdater;
  late Directory cacheDir;
  late StringBuffer errorOutput;

  setUp(() {
    pubUpdater = _MockPubUpdater();
    cacheDir = Directory.systemTemp.createTempSync('pubup_cache_test');
    errorOutput = StringBuffer();
  });

  tearDown(() {
    cacheDir.deleteSync(recursive: true);
  });

  group('isUpdateCheckDisabled', () {
    test('returns true when CI=true', () {
      expect(isUpdateCheckDisabled({'CI': 'true'}), isTrue);
    });

    test('returns true when disable env is empty', () {
      expect(
        isUpdateCheckDisabled({disableUpdateCheckEnv: ''}),
        isTrue,
      );
    });

    test('returns true when disable env is 1', () {
      expect(
        isUpdateCheckDisabled({disableUpdateCheckEnv: '1'}),
        isTrue,
      );
    });

    test('returns true for other truthy disable values', () {
      expect(
        isUpdateCheckDisabled({disableUpdateCheckEnv: 'yes'}),
        isTrue,
      );
    });

    test('returns false when disable env is 0', () {
      expect(
        isUpdateCheckDisabled({disableUpdateCheckEnv: '0'}),
        isFalse,
      );
    });

    test('returns false when disable env is false', () {
      expect(
        isUpdateCheckDisabled({disableUpdateCheckEnv: 'false'}),
        isFalse,
      );
    });

    test('returns false when neither CI nor disable env is set', () {
      expect(isUpdateCheckDisabled({}), isFalse);
    });

    test('returns true when isInteractive is false', () {
      expect(
        isUpdateCheckDisabled({}, isInteractive: false),
        isTrue,
      );
    });

    test('returns false when isInteractive is true and env is empty', () {
      expect(
        isUpdateCheckDisabled({}, isInteractive: true),
        isFalse,
      );
    });
  });

  group('resolveUpdateCacheDir', () {
    test('uses PUB_CACHE when set', () {
      final dir = resolveUpdateCacheDir({'PUB_CACHE': '/custom/cache'});
      expect(dir.path, '/custom/cache/pubup');
    });

    test('falls back to HOME/.pub-cache', () {
      final dir = resolveUpdateCacheDir({'HOME': '/home/user'});
      expect(dir.path, '/home/user/.pub-cache/pubup');
    });
  });

  group('checkForUpdate', () {
    test('skips when CI=true', () async {
      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        cacheDir: cacheDir,
        environment: {'CI': 'true'},
        isInteractive: true,
      );

      verifyNever(() => pubUpdater.getLatestVersion(any()));
      expect(errorOutput.toString(), isEmpty);
    });

    test('skips when PUBUP_DISABLE_UPDATE_CHECK=1', () async {
      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        cacheDir: cacheDir,
        environment: {disableUpdateCheckEnv: '1'},
        isInteractive: true,
      );

      verifyNever(() => pubUpdater.getLatestVersion(any()));
      expect(errorOutput.toString(), isEmpty);
    });

    test('skips when isInteractive is false (no TTY)', () async {
      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        cacheDir: cacheDir,
        environment: {},
        isInteractive: false,
      );

      verifyNever(() => pubUpdater.getLatestVersion(any()));
      expect(errorOutput.toString(), isEmpty);
    });

    test('skips when cache file is fresh', () async {
      final cacheFile = File('${cacheDir.path}/last_update_check');
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsString('cached');

      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        cacheDir: cacheDir,
        environment: {},
        isInteractive: true,
        cacheDuration: const Duration(hours: 24),
      );

      verifyNever(() => pubUpdater.getLatestVersion(any()));
      expect(errorOutput.toString(), isEmpty);
    });

    test('calls pub.dev when cache file is missing', () async {
      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenAnswer((_) async => '0.2.0');

      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        cacheDir: cacheDir,
        environment: {},
        isInteractive: true,
      );

      verify(() => pubUpdater.getLatestVersion(pubupPackageName)).called(1);
      expect(File('${cacheDir.path}/last_update_check').existsSync(), isTrue);
      expect(errorOutput.toString(), isEmpty);
    });

    test('calls pub.dev when cache file is stale', () async {
      final cacheFile = File('${cacheDir.path}/last_update_check');
      await cacheFile.parent.create(recursive: true);
      await cacheFile.writeAsString('stale');
      await cacheFile.setLastModified(
        DateTime.now().subtract(const Duration(hours: 25)),
      );

      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenAnswer((_) async => '0.2.0');

      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        cacheDir: cacheDir,
        environment: {},
        isInteractive: true,
        cacheDuration: const Duration(hours: 24),
      );

      verify(() => pubUpdater.getLatestVersion(pubupPackageName)).called(1);
      expect(errorOutput.toString(), isEmpty);
    });

    test('prints notice when latest differs from current', () async {
      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenAnswer((_) async => '0.3.0');

      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        cacheDir: cacheDir,
        environment: {},
        isInteractive: true,
      );

      expect(
        errorOutput.toString(),
        contains('pubup 0.3.0 is available (you have 0.2.0)'),
      );
      expect(errorOutput.toString(), contains('pubup update'));
    });

    test('is silent when latest equals current', () async {
      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenAnswer((_) async => '0.2.0');

      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        cacheDir: cacheDir,
        environment: {},
        isInteractive: true,
      );

      expect(errorOutput.toString(), isEmpty);
    });

    test('swallows exceptions from getLatestVersion', () async {
      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenThrow(Exception('network error'));

      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        cacheDir: cacheDir,
        environment: {},
        isInteractive: true,
      );

      expect(errorOutput.toString(), isEmpty);
      expect(File('${cacheDir.path}/last_update_check').existsSync(), isTrue);
    });

    test('uses Platform.environment when environment is omitted', () async {
      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenAnswer((_) async => '0.2.0');

      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        cacheDir: cacheDir,
        isInteractive: true,
      );

      verify(() => pubUpdater.getLatestVersion(pubupPackageName)).called(1);
    });

    test('uses resolveUpdateCacheDir when cacheDir is omitted', () async {
      final homeDir = Directory.systemTemp.createTempSync('pubup_home_test');
      addTearDown(() => homeDir.deleteSync(recursive: true));

      when(() => pubUpdater.getLatestVersion(pubupPackageName))
          .thenAnswer((_) async => '0.2.0');

      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        environment: {'HOME': homeDir.path},
        isInteractive: true,
      );

      expect(
        File('${homeDir.path}/.pub-cache/pubup/last_update_check').existsSync(),
        isTrue,
      );
    });

    test('swallows TimeoutException', () async {
      when(() => pubUpdater.getLatestVersion(pubupPackageName)).thenAnswer(
        (_) => Future<String>.delayed(
          const Duration(seconds: 5),
          () => '0.3.0',
        ),
      );

      await checkForUpdate(
        currentVersion: '0.2.0',
        errorOutput: errorOutput,
        pubUpdater: pubUpdater,
        cacheDir: cacheDir,
        environment: {},
        isInteractive: true,
        timeout: const Duration(milliseconds: 50),
      );

      expect(errorOutput.toString(), isEmpty);
      expect(File('${cacheDir.path}/last_update_check').existsSync(), isTrue);
    });
  });
}
