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
}) =>
    OutdatedPackage(
      package: name,
      kind: kind,
      currentVersion: current,
      resolvableVersion: resolvable,
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
          'http': const DependencyEntry(
            source: 'hosted',
            constraint: '^1.0.0',
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
      expect(result.candidates.first.name, 'http');
      expect(result.candidates.first.targetConstraint, '^1.2.0');
      expect(result.candidates.first.targetVersion, '1.2.0');
      expect(result.candidates.first.declaredConstraint, '^1.0.0');
      expect(result.report.attempted, 1);
    });

    test('skips path dependencies', () async {
      final outdated = [
        _pkg(name: 'local_pkg'),
      ];
      final deps = PubspecDependencies(
        direct: {
          'local_pkg': const DependencyEntry(source: 'path'),
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

    test('skips git dependencies', () async {
      final outdated = [_pkg(name: 'git_pkg')];
      final deps = PubspecDependencies(
        direct: {
          'git_pkg': const DependencyEntry(source: 'git'),
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
          'http': const DependencyEntry(
            source: 'hosted',
            constraint: '^1.2.0',
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
      expect(result.report.skippedUpToDate, 1);
    });

    test('skips transitive dependencies', () async {
      final outdated = [
        _pkg(name: 'transitive_dep', kind: 'transitive'),
      ];
      final deps = PubspecDependencies(direct: {}, dev: {});

      final result = await collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
    });

    test('skips dev deps when includeDev is false', () async {
      final outdated = [
        _pkg(name: 'test_pkg', kind: 'dev'),
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

    test('handles build metadata in constraints', () async {
      final outdated = [
        _pkg(
          name: 'provider',
          current: '6.1.5+1',
          resolvable: '6.1.5+1',
        ),
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
          'http': const DependencyEntry(
            source: 'hosted',
            constraint: '^1.0.0',
          ),
          'yaml': const DependencyEntry(
            source: 'hosted',
            constraint: '^3.0.0',
          ),
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

      test('minor level falls back to in-bound version when resolvable is '
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
    });
  });
}
