import 'package:pubup/src/candidate_collector.dart';
import 'package:pubup/src/outdated_runner.dart';
import 'package:pubup/src/pubspec_parser.dart';
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

void main() {
  group('collectCandidates', () {
    test('collects hosted deps that need updating', () {
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

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, hasLength(1));
      expect(result.candidates.first.name, 'http');
      expect(result.candidates.first.targetConstraint, '^1.2.0');
      expect(result.candidates.first.declaredConstraint, '^1.0.0');
      expect(result.report.attempted, 1);
    });

    test('skips path dependencies', () {
      final outdated = [
        _pkg(name: 'local_pkg'),
      ];
      final deps = PubspecDependencies(
        direct: {
          'local_pkg': const DependencyEntry(source: 'path'),
        },
        dev: {},
      );

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedNonHosted, 1);
    });

    test('skips git dependencies', () {
      final outdated = [_pkg(name: 'git_pkg')];
      final deps = PubspecDependencies(
        direct: {
          'git_pkg': const DependencyEntry(source: 'git'),
        },
        dev: {},
      );

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedNonHosted, 1);
    });

    test('skips sdk dependencies', () {
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

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedNonHosted, 1);
    });

    test('skips "any" constraints', () {
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

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedNonstandard, 1);
    });

    test('skips non-standard constraints like >=1.0.0 <2.0.0', () {
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

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedNonstandard, 1);
    });

    test('skips already up-to-date dependencies', () {
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

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedUpToDate, 1);
    });

    test('skips transitive dependencies', () {
      final outdated = [
        _pkg(name: 'transitive_dep', kind: 'transitive'),
      ];
      final deps = PubspecDependencies(direct: {}, dev: {});

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
    });

    test('skips dev deps when includeDev is false', () {
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

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: false,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedKind, 1);
    });

    test('collects dev deps when includeDev is true', () {
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

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, hasLength(1));
      expect(result.candidates.first.kind, 'dev');
    });

    test('skips unknown dependencies not in pubspec', () {
      final outdated = [_pkg(name: 'mystery_dep')];
      final deps = const PubspecDependencies(direct: {}, dev: {});

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, isEmpty);
      expect(result.report.skippedUnknown, 1);
    });

    test('handles build metadata in constraints', () {
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

      final result = collectCandidates(
        outdatedPackages: outdated,
        deps: deps,
        includeDev: true,
      );

      expect(result.candidates, hasLength(1));
      expect(result.candidates.first.targetConstraint, '^6.1.5+1');
    });

    test('handles multiple candidates in one pass', () {
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

      final result = collectCandidates(
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
  });
}
