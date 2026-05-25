import 'package:pub_semver/pub_semver.dart';
import 'package:pubup/src/version_resolver.dart';
import 'package:test/test.dart';

VersionsFetcher _fixed(List<String> versions) =>
    (_) async => List.of(versions);

VersionsFetcher _shouldNotBeCalled() => (_) async {
      fail('fetchVersions should not be called');
    };

VersionsFetcher _throwing() => (_) async => throw Exception('network down');

void main() {
  group('versionFitsBound', () {
    test('major level always fits', () {
      expect(
        versionFitsBound(
          level: BumpLevel.major,
          current: Version.parse('1.2.3'),
          candidate: Version.parse('99.0.0'),
        ),
        isTrue,
      );
    });

    test('minor level requires same major segment', () {
      final current = Version.parse('1.2.3');
      expect(
        versionFitsBound(
          level: BumpLevel.minor,
          current: current,
          candidate: Version.parse('1.5.0'),
        ),
        isTrue,
      );
      expect(
        versionFitsBound(
          level: BumpLevel.minor,
          current: current,
          candidate: Version.parse('2.0.0'),
        ),
        isFalse,
      );
    });

    test('patch level requires same major and minor segments', () {
      final current = Version.parse('1.2.3');
      expect(
        versionFitsBound(
          level: BumpLevel.patch,
          current: current,
          candidate: Version.parse('1.2.9'),
        ),
        isTrue,
      );
      expect(
        versionFitsBound(
          level: BumpLevel.patch,
          current: current,
          candidate: Version.parse('1.3.0'),
        ),
        isFalse,
      );
    });

    test('0.x literal segment semantics under minor', () {
      final current = Version.parse('0.1.2');
      expect(
        versionFitsBound(
          level: BumpLevel.minor,
          current: current,
          candidate: Version.parse('0.5.0'),
        ),
        isTrue,
      );
      expect(
        versionFitsBound(
          level: BumpLevel.minor,
          current: current,
          candidate: Version.parse('1.0.0'),
        ),
        isFalse,
      );
    });

    test('0.x literal segment semantics under patch', () {
      final current = Version.parse('0.1.2');
      expect(
        versionFitsBound(
          level: BumpLevel.patch,
          current: current,
          candidate: Version.parse('0.1.9'),
        ),
        isTrue,
      );
      expect(
        versionFitsBound(
          level: BumpLevel.patch,
          current: current,
          candidate: Version.parse('0.2.0'),
        ),
        isFalse,
      );
    });
  });

  group('bumpLevelFromString', () {
    test('parses each known value', () {
      expect(bumpLevelFromString('major'), BumpLevel.major);
      expect(bumpLevelFromString('minor'), BumpLevel.minor);
      expect(bumpLevelFromString('patch'), BumpLevel.patch);
    });

    test('falls back to major for unknown values', () {
      expect(bumpLevelFromString('whatever'), BumpLevel.major);
    });
  });

  group('pickTargetVersion', () {
    test('major level returns resolvable without fetching', () async {
      final target = await pickTargetVersion(
        level: BumpLevel.major,
        current: '1.2.3',
        resolvable: '5.0.0',
        packageName: 'foo',
        fetchVersions: _shouldNotBeCalled(),
      );
      expect(target, '5.0.0');
    });

    test('minor returns resolvable when in same major', () async {
      final target = await pickTargetVersion(
        level: BumpLevel.minor,
        current: '1.2.3',
        resolvable: '1.5.0',
        packageName: 'foo',
        fetchVersions: _shouldNotBeCalled(),
      );
      expect(target, '1.5.0');
    });

    test('minor falls back to highest in-bound version above current',
        () async {
      final target = await pickTargetVersion(
        level: BumpLevel.minor,
        current: '1.2.3',
        resolvable: '2.0.0',
        packageName: 'foo',
        fetchVersions: _fixed([
          '1.2.3',
          '1.4.0',
          '1.5.0',
          '1.5.1',
          '2.0.0',
          '2.1.0',
        ]),
      );
      expect(target, '1.5.1');
    });

    test('patch falls back to highest patch within current minor', () async {
      final target = await pickTargetVersion(
        level: BumpLevel.patch,
        current: '1.2.3',
        resolvable: '1.5.0',
        packageName: 'foo',
        fetchVersions: _fixed([
          '1.2.3',
          '1.2.5',
          '1.2.9',
          '1.3.0',
          '1.5.0',
        ]),
      );
      expect(target, '1.2.9');
    });

    test('0.x minor: 0.1.2 → 0.5.0 allowed', () async {
      final target = await pickTargetVersion(
        level: BumpLevel.minor,
        current: '0.1.2',
        resolvable: '1.0.0',
        packageName: 'foo',
        fetchVersions: _fixed([
          '0.1.2',
          '0.1.5',
          '0.5.0',
          '1.0.0',
        ]),
      );
      expect(target, '0.5.0');
    });

    test('returns null when no qualifying version is greater than current',
        () async {
      final target = await pickTargetVersion(
        level: BumpLevel.minor,
        current: '1.2.3',
        resolvable: '2.0.0',
        packageName: 'foo',
        fetchVersions: _fixed([
          '1.0.0',
          '1.2.3',
          '2.0.0',
          '2.1.0',
        ]),
      );
      expect(target, isNull);
    });

    test('skips pre-releases when current is stable', () async {
      final target = await pickTargetVersion(
        level: BumpLevel.minor,
        current: '1.2.3',
        resolvable: '2.0.0',
        packageName: 'foo',
        fetchVersions: _fixed([
          '1.2.5',
          '1.6.0-beta.1',
          '2.0.0',
        ]),
      );
      expect(target, '1.2.5');
    });

    test('returns null when fetched list is empty', () async {
      final target = await pickTargetVersion(
        level: BumpLevel.patch,
        current: '1.2.3',
        resolvable: '2.0.0',
        packageName: 'foo',
        fetchVersions: _fixed(const []),
      );
      expect(target, isNull);
    });

    test('returns null when fetcher throws', () async {
      final target = await pickTargetVersion(
        level: BumpLevel.patch,
        current: '1.2.3',
        resolvable: '2.0.0',
        packageName: 'foo',
        fetchVersions: _throwing(),
      );
      expect(target, isNull);
    });

    test('ignores unparseable version strings', () async {
      final target = await pickTargetVersion(
        level: BumpLevel.minor,
        current: '1.2.3',
        resolvable: '2.0.0',
        packageName: 'foo',
        fetchVersions: _fixed([
          'not-a-version',
          '1.4.0',
          '2.0.0',
        ]),
      );
      expect(target, '1.4.0');
    });
  });
}
