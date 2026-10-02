import 'package:pubup/src/candidate_collector.dart';
import 'package:pubup/src/outdated_runner.dart';
import 'package:pubup/src/pubspec_parser.dart';
import 'package:pubup/src/version_resolver.dart';
import 'package:test/test.dart';

OutdatedPackage _pkg({
  required String name,
  String kind = 'direct',
  String current = '1.0.0',
  String resolvable = '1.1.0',
  String? latest,
}) =>
    OutdatedPackage(
      package: name,
      kind: kind,
      currentVersion: current,
      resolvableVersion: resolvable,
      latestVersion: latest,
    );

PubspecDependencies _hosted(Map<String, String> direct) => PubspecDependencies(
      direct: {
        for (final entry in direct.entries)
          entry.key: DependencyEntry(source: 'hosted', constraint: entry.value),
      },
      dev: const {},
    );

VersionsFetcher _fixed(Map<String, List<String>> byName) => (name) async {
      return List.of(byName[name] ?? const []);
    };

void main() {
  group('collectCandidates', () {
    test('collects hosted deps that need updating', () async {
      final outdated = [
        _pkg(name: 'http', current: '1.0.0', resolvable: '1.2.0'),
      ];
      final deps = PubspecDependencies(
        direct: {
          'http': const DependencyEntry(source: 'hosted', constraint: '^1.0.0'),
        },
        dev: {},
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, hasLength(1));
      expect(result.candidates.first.name, 'http');
      expect(result.candidates.first.targetConstraint, '^1.2.0');
      expect(result.candidates.first.targetVersion, '1.2.0');
      expect(result.candidates.first.declaredConstraint, '^1.0.0');
      expect(result.report.attempted, 1);
    });

    test('skips path dependencies', () async {
      final outdated = [_pkg(name: 'local_pkg')];
      final deps = PubspecDependencies(
        direct: {'local_pkg': const DependencyEntry(source: 'path')},
        dev: {},
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedNonHosted, 1);
    });

    test('skips git dependencies', () async {
      final outdated = [_pkg(name: 'git_pkg')];
      final deps = PubspecDependencies(
        direct: {'git_pkg': const DependencyEntry(source: 'git')},
        dev: {},
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedNonHosted, 1);
    });

    test('skips sdk dependencies', () async {
      final outdated = [_pkg(name: 'flutter')];
      final deps = PubspecDependencies(
        direct: {
          'flutter': const DependencyEntry(
            source: 'sdk',
            constraint: 'flutter',
          ),
        },
        dev: {},
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedNonHosted, 1);
    });

    test('skips "any" constraints', () async {
      final outdated = [_pkg(name: 'loose_dep')];
      final deps = PubspecDependencies(
        direct: {
          'loose_dep': const DependencyEntry(
            source: 'hosted',
            constraint: 'any',
          ),
        },
        dev: {},
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedNonstandard, 1);
    });

    test('skips non-standard constraints like >=1.0.0 <2.0.0', () async {
      final outdated = [_pkg(name: 'ranged')];
      final deps = PubspecDependencies(
        direct: {
          'ranged': const DependencyEntry(
            source: 'hosted',
            constraint: '>=1.0.0 <2.0.0',
          ),
        },
        dev: {},
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedNonstandard, 1);
    });

    test('skips already up-to-date dependencies', () async {
      final outdated = [
        _pkg(name: 'http', current: '1.2.0', resolvable: '1.2.0'),
      ];
      final deps = PubspecDependencies(
        direct: {
          'http': const DependencyEntry(source: 'hosted', constraint: '^1.2.0'),
        },
        dev: {},
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedUpToDate, 1);
    });

    test('skips transitive dependencies', () async {
      final outdated = [_pkg(name: 'transitive_dep', kind: 'transitive')];
      final deps = PubspecDependencies(direct: {}, dev: {});

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
    });

    test('skips dev deps when includeDev is false', () async {
      final outdated = [_pkg(name: 'test_pkg', kind: 'dev')];
      final deps = PubspecDependencies(
        direct: {},
        dev: {
          'test_pkg': const DependencyEntry(
            source: 'hosted',
            constraint: '^1.0.0',
          ),
        },
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: false,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedKind, 1);
    });

    test('collects dev deps when includeDev is true', () async {
      final outdated = [
        _pkg(name: 'test_pkg', kind: 'dev', resolvable: '2.0.0'),
      ];
      final deps = PubspecDependencies(
        direct: {},
        dev: {
          'test_pkg': const DependencyEntry(
            source: 'hosted',
            constraint: '^1.0.0',
          ),
        },
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, hasLength(1));
      expect(result.candidates.first.kind, 'dev');
    });

    test('skips unknown dependencies not in pubspec', () async {
      final outdated = [_pkg(name: 'mystery_dep')];
      final deps = const PubspecDependencies(direct: {}, dev: {});

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedUnknown, 1);
    });

    test('skips declared dependencies with an unrecognised source', () async {
      final outdated = [_pkg(name: 'odd_dep')];
      final deps = PubspecDependencies(
        direct: {'odd_dep': const DependencyEntry(source: 'unknown')},
        dev: {},
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedUnknown, 1);
      expect(result.report.skippedNonstandard, 0);
    });

    test('handles build metadata in constraints', () async {
      final outdated = [
        _pkg(name: 'provider', current: '6.1.5+1', resolvable: '6.1.5+1'),
      ];
      final deps = PubspecDependencies(
        direct: {
          'provider': const DependencyEntry(
            source: 'hosted',
            constraint: '^6.1.5',
          ),
        },
        dev: {},
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, hasLength(1));
      expect(result.candidates.first.targetConstraint, '^6.1.5+1');
    });

    test('handles multiple candidates in one pass', () async {
      final outdated = [
        _pkg(name: 'http', resolvable: '1.2.0'),
        _pkg(name: 'yaml', resolvable: '3.2.0'),
        _pkg(name: 'test_pkg', kind: 'dev', resolvable: '2.0.0'),
        _pkg(name: 'path_dep'),
        _pkg(name: 'up_to_date', resolvable: '1.0.0'),
      ];
      final deps = PubspecDependencies(
        direct: {
          'http': const DependencyEntry(source: 'hosted', constraint: '^1.0.0'),
          'yaml': const DependencyEntry(source: 'hosted', constraint: '^3.0.0'),
          'path_dep': const DependencyEntry(source: 'path'),
          'up_to_date': const DependencyEntry(
            source: 'hosted',
            constraint: '^1.0.0',
          ),
        },
        dev: {
          'test_pkg': const DependencyEntry(
            source: 'hosted',
            constraint: '^1.0.0',
          ),
        },
      );

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, hasLength(3));
      expect(
        result.candidates.map((c) => c.name),
        containsAll(['http', 'yaml', 'test_pkg']),
      );
      expect(result.report.skippedNonHosted, 1);
      expect(result.report.skippedUpToDate, 1);
    });

    group('with bumpLevel', () {
      test('major level uses resolvable version (default)', () async {
        final outdated = [
          _pkg(name: 'http', current: '1.2.3', resolvable: '2.5.0'),
        ];
        final deps = PubspecDependencies(
          direct: {
            'http': const DependencyEntry(
              source: 'hosted',
              constraint: '^1.2.3',
            ),
          },
          dev: {},
        );

        final result = await collectCandidates(
          outdatedPackages: outdated,
          deps: deps,
          includeDev: true,
          fetchVersions: (_) async => fail('should not be called'),
        );

        expect(result.candidates, hasLength(1));
        expect(result.candidates.first.targetConstraint, '^2.5.0');
      });

      test('minor level uses resolvable when same major', () async {
        final outdated = [
          _pkg(name: 'http', current: '1.2.3', resolvable: '1.5.0'),
        ];
        final deps = PubspecDependencies(
          direct: {
            'http': const DependencyEntry(
              source: 'hosted',
              constraint: '^1.2.3',
            ),
          },
          dev: {},
        );

        final result = await collectCandidates(
          outdatedPackages: outdated,
          deps: deps,
          includeDev: true,
          bumpLevel: BumpLevel.minor,
          fetchVersions: (_) async => fail('should not be called'),
        );

        expect(result.candidates, hasLength(1));
        expect(result.candidates.first.targetConstraint, '^1.5.0');
      });

      test(
          'minor level falls back to in-bound version when resolvable is '
          'a major bump', () async {
        final outdated = [
          _pkg(name: 'http', current: '1.2.3', resolvable: '2.0.0'),
        ];
        final deps = PubspecDependencies(
          direct: {
            'http': const DependencyEntry(
              source: 'hosted',
              constraint: '^1.2.3',
            ),
          },
          dev: {},
        );

        final result = await collectCandidates(
          outdatedPackages: outdated,
          deps: deps,
          includeDev: true,
          bumpLevel: BumpLevel.minor,
          fetchVersions: _fixed({
            'http': ['1.2.3', '1.4.0', '1.5.0', '2.0.0'],
          }),
        );

        expect(result.candidates, hasLength(1));
        expect(result.candidates.first.targetConstraint, '^1.5.0');
      });

      test('patch level falls back to highest in-bound patch', () async {
        final outdated = [
          _pkg(name: 'http', current: '1.2.3', resolvable: '1.5.0'),
        ];
        final deps = PubspecDependencies(
          direct: {
            'http': const DependencyEntry(
              source: 'hosted',
              constraint: '^1.2.3',
            ),
          },
          dev: {},
        );

        final result = await collectCandidates(
          outdatedPackages: outdated,
          deps: deps,
          includeDev: true,
          bumpLevel: BumpLevel.patch,
          fetchVersions: _fixed({
            'http': ['1.2.3', '1.2.5', '1.2.9', '1.3.0', '1.5.0'],
          }),
        );

        expect(result.candidates, hasLength(1));
        expect(result.candidates.first.targetConstraint, '^1.2.9');
      });

      test('bumps skipByBumpFilter when no in-bound version exists', () async {
        final outdated = [
          _pkg(name: 'http', current: '1.2.3', resolvable: '2.0.0'),
        ];
        final deps = PubspecDependencies(
          direct: {
            'http': const DependencyEntry(
              source: 'hosted',
              constraint: '^1.2.3',
            ),
          },
          dev: {},
        );

        final result = await collectCandidates(
          outdatedPackages: outdated,
          deps: deps,
          includeDev: true,
          bumpLevel: BumpLevel.minor,
          fetchVersions: _fixed({
            'http': ['1.2.3', '2.0.0'],
          }),
        );

        expect(result.candidates, isEmpty);
        expect(result.report.skippedByBumpFilter, 1);
        expect(result.report.attempted, 0);
      });

      test('skips out-of-bound deps when no version fetcher is given',
          () async {
        final result = await collectCandidates(
          outdatedPackages: [
            _pkg(name: 'http', current: '1.2.3', resolvable: '2.0.0'),
          ],
          deps: _hosted({'http': '^1.2.3'}),
          includeDev: true,
          bumpLevel: BumpLevel.minor,
        );

        expect(result.candidates, isEmpty);
        expect(result.report.skippedByBumpFilter, 1);
      });
    });

    group('with pre-release resolvable versions', () {
      test('falls back to the newest stable version', () async {
        final result = await collectCandidates(
          outdatedPackages: [
            _pkg(
              name: 'sentry_flutter',
              current: '9.30.0',
              resolvable: '10.0.0-rc.2',
            ),
          ],
          deps: _hosted({'sentry_flutter': '^9.30.0'}),
          includeDev: true,
          fetchVersions: _fixed({
            'sentry_flutter': ['9.30.0', '9.30.1', '10.0.0-rc.2'],
          }),
        );

        expect(result.candidates, hasLength(1));
        expect(result.candidates.first.targetConstraint, '^9.30.1');
      });

      test('counts prerelease-only skips separately from --bump', () async {
        final result = await collectCandidates(
          outdatedPackages: [
            _pkg(
              name: 'sentry_flutter',
              current: '9.30.1',
              resolvable: '10.0.0-rc.2',
            ),
          ],
          deps: _hosted({'sentry_flutter': '^9.30.1'}),
          includeDev: true,
          fetchVersions: _fixed({
            'sentry_flutter': ['9.30.1', '10.0.0-rc.2'],
          }),
        );

        expect(result.candidates, isEmpty);
        expect(result.report.skippedPrerelease, 1);
        expect(result.report.skippedByBumpFilter, 0);
      });

      test('accepts the pre-release when allowPrereleases is set', () async {
        final result = await collectCandidates(
          outdatedPackages: [
            _pkg(
              name: 'sentry_flutter',
              current: '9.30.0',
              resolvable: '10.0.0-rc.2',
            ),
          ],
          deps: _hosted({'sentry_flutter': '^9.30.0'}),
          includeDev: true,
          allowPrereleases: true,
          fetchVersions: (_) async => fail('should not be called'),
        );

        expect(result.candidates.first.targetConstraint, '^10.0.0-rc.2');
      });
    });

    group('heldBack', () {
      test('reports declared deps whose latest exceeds resolvable', () async {
        final result = await collectCandidates(
          outdatedPackages: [
            _pkg(
              name: 'equatable',
              current: '2.1.0',
              resolvable: '2.1.0',
              latest: '3.0.0',
            ),
            _pkg(
              name: 'latlong2',
              current: '0.9.0',
              resolvable: '0.9.1',
              latest: '0.10.1',
            ),
          ],
          deps: _hosted({'equatable': '^2.1.0', 'latlong2': '^0.9.0'}),
          includeDev: true,
        );

        expect(result.heldBack.map((h) => h.name), ['equatable', 'latlong2']);
        final equatable = result.heldBack.first;
        expect(equatable.kind, 'direct');
        expect(equatable.resolvableVersion, '2.1.0');
        expect(equatable.latestVersion, '3.0.0');
        expect(result.candidates.map((c) => c.name), ['latlong2']);
      });

      test('reports deps with non-standard constraints', () async {
        final result = await collectCandidates(
          outdatedPackages: [
            _pkg(name: 'ranged', resolvable: '1.5.0', latest: '2.0.0'),
          ],
          deps: _hosted({'ranged': '>=1.0.0 <2.0.0'}),
          includeDev: true,
        );

        expect(result.report.skippedNonstandard, 1);
        expect(result.heldBack.map((h) => h.name), ['ranged']);
      });

      test('ignores deps that are not held back', () async {
        final result = await collectCandidates(
          outdatedPackages: [
            _pkg(name: 'at_latest', resolvable: '1.1.0', latest: '1.1.0'),
            _pkg(name: 'no_latest', resolvable: '1.1.0'),
            _pkg(name: 'bad_latest', resolvable: '1.1.0', latest: 'nope'),
            _pkg(name: 'pre_latest', resolvable: '1.1.0', latest: '2.0.0-dev'),
          ],
          deps: _hosted({
            'at_latest': '^1.0.0',
            'no_latest': '^1.0.0',
            'bad_latest': '^1.0.0',
            'pre_latest': '^1.0.0',
          }),
          includeDev: true,
        );

        expect(result.heldBack, isEmpty);
      });

      test('ignores transitive, non-hosted, and excluded dev deps', () async {
        final result = await collectCandidates(
          outdatedPackages: [
            _pkg(name: 'transitive', kind: 'transitive', latest: '9.0.0'),
            _pkg(name: 'local', latest: '9.0.0'),
            _pkg(name: 'lints', kind: 'dev', latest: '9.0.0'),
          ],
          deps: PubspecDependencies(
            direct: {'local': const DependencyEntry(source: 'path')},
            dev: {
              'lints': const DependencyEntry(
                source: 'hosted',
                constraint: '^1.0.0',
              ),
            },
          ),
          includeDev: false,
        );

        expect(result.heldBack, isEmpty);
      });
    });
  });
}
