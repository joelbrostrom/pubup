import 'package:pubup/src/candidate_collector.dart';
import 'package:pubup/src/reporter.dart';
import 'package:test/test.dart';

HeldBackDependency _held(
  String name, {
  String kind = 'direct',
  String resolvable = '1.0.0',
  String latest = '2.0.0',
}) =>
    HeldBackDependency(
      name: name,
      kind: kind,
      resolvableVersion: resolvable,
      latestVersion: latest,
    );

void main() {
  group('printWorkspaceReport', () {
    test('prints held-back deps once each, sorted, above the summary', () {
      final report = WorkspaceReport(repoRoot: '/repo', command: 'flutter')
        ..heldBack.addAll([
          _held('latlong2', resolvable: '0.9.1', latest: '0.10.1'),
          _held('equatable', resolvable: '2.1.0', latest: '3.0.0'),
          _held('latlong2', resolvable: '0.9.1', latest: '0.10.1'),
          _held('freezed', kind: 'dev', resolvable: '4.0.1', latest: '4.0.2'),
        ]);
      final output = StringBuffer();

      final exitCode = printWorkspaceReport(
        report,
        dryRun: false,
        output: output,
      );

      final text = output.toString();
      expect(exitCode, 0);
      expect(text, contains('Held back (3)'));
      expect(
        text,
        contains('  equatable  direct  resolvable 2.1.0  latest 3.0.0'),
      );
      expect(text, contains('  freezed    dev     resolvable 4.0.1  latest'));
      expect('latlong2'.allMatches(text), hasLength(1));
      expect(text.indexOf('equatable'), lessThan(text.indexOf('freezed')));
      expect(text.indexOf('Held back'), lessThan(text.indexOf('Summary')));
    });

    test('prints held-back deps above failures', () {
      final report = WorkspaceReport(repoRoot: '/repo', command: 'dart')
        ..heldBack.add(_held('equatable'))
        ..failed = 1
        ..failures.add('http: version solving failed');
      final output = StringBuffer();

      final exitCode = printWorkspaceReport(
        report,
        dryRun: false,
        output: output,
      );

      final text = output.toString();
      expect(exitCode, 1);
      expect(text.indexOf('Held back'), lessThan(text.indexOf('Failures')));
    });

    test('omits the held-back section when nothing is held back', () {
      final output = StringBuffer();

      printWorkspaceReport(
        WorkspaceReport(repoRoot: '/repo', command: 'dart'),
        dryRun: false,
        output: output,
      );

      expect(output.toString(), isNot(contains('Held back')));
    });

    test('describes prerelease-only skips', () {
      final report = WorkspaceReport(repoRoot: '/repo', command: 'dart')
        ..skippedUpToDate = 4
        ..skippedPrerelease = 2;
      final output = StringBuffer();

      printWorkspaceReport(report, dryRun: false, output: output);

      expect(
        output.toString(),
        contains('Skipped  4 up-to-date, 2 prerelease-only'),
      );
    });

    test('counts updated constraints and dependencies', () {
      final output = StringBuffer();

      printWorkspaceReport(
        WorkspaceReport(repoRoot: '/repo', command: 'dart')
          ..attempted = 2
          ..changed = 5,
        dryRun: false,
        output: output,
      );

      expect(
        output.toString(),
        contains('Updated  5 constraints across 2 dependencies'),
      );
    });

    test('uses singular nouns for a single update', () {
      final output = StringBuffer();

      printWorkspaceReport(
        WorkspaceReport(repoRoot: '/repo', command: 'dart')
          ..attempted = 1
          ..changed = 1,
        dryRun: false,
        output: output,
      );

      expect(
        output.toString(),
        contains('Updated  1 constraint across 1 dependency\n'),
      );
    });

    test('ends with the dry-run notice in dry-run mode', () {
      final output = StringBuffer();

      printWorkspaceReport(
        WorkspaceReport(repoRoot: '/repo', command: 'dart'),
        dryRun: true,
        output: output,
      );

      expect(
        output.toString(),
        endsWith('\nDry-run mode: no files were changed.\n'),
      );
    });

    test('describes deps skipped by the --package filter', () {
      final output = StringBuffer();

      printWorkspaceReport(
        WorkspaceReport(repoRoot: '/repo', command: 'dart')
          ..skippedFilteredCoordination = 3,
        dryRun: false,
        output: output,
      );

      expect(output.toString(), contains('Skipped  3 filtered (--package)'));
    });

    test('fails on scan failures and lists them under Failures', () {
      final output = StringBuffer();

      final exitCode = printWorkspaceReport(
        WorkspaceReport(repoRoot: '/repo', command: 'dart')
          ..scanFailures.add('packages/a: pub outdated failed'),
        dryRun: false,
        output: output,
      );

      expect(exitCode, 1);
      expect(output.toString(), contains('Failures (1)'));
      expect(output.toString(), contains('  scan failed:\n'));
    });
  });

  group('failure formatting', () {
    String printFailure(String failure) {
      final output = StringBuffer();
      printWorkspaceReport(
        WorkspaceReport(repoRoot: '/repo', command: 'dart')
          ..failed = 1
          ..failures.add(failure),
        dryRun: false,
        output: output,
      );
      final text = output.toString();
      return text.substring(
        text.indexOf('-\n') + 2,
        text.indexOf('\nSummary'),
      );
    }

    test('prints messages without a package prefix as-is', () {
      expect(printFailure('  something broke  '), '\n  something broke\n');
    });

    test('prints only the name when the message is empty', () {
      expect(printFailure('http:'), '\n  http:\n');
    });

    test('word-wraps long messages under the package name', () {
      final words = List.filled(20, 'resolution').join(' ');

      final printed = printFailure('http: $words');

      final lines = printed.split('\n').where((l) => l.isNotEmpty).toList();
      expect(lines.first, '  http:');
      expect(lines.length, greaterThan(2));
      for (final line in lines.skip(1)) {
        expect(line, startsWith('    resolution'));
        expect(line.length, lessThanOrEqualTo(80));
      }
      expect(
        lines.skip(1).map((l) => l.trim()).join(' '),
        words,
      );
    });

    test('hard-breaks words longer than the wrap width', () {
      final token = 'x' * 100;

      final printed = printFailure('http: $token');

      expect(printed, '\n  http:\n    ${'x' * 76}\n    ${'x' * 24}\n');
    });

    test('keeps blank lines between paragraphs', () {
      final printed = printFailure('http: first\n\nsecond');

      expect(printed, '\n  http:\n    first\n    \n    second\n');
    });
  });

  group('printReport', () {
    test('prints held-back deps and prerelease-only skips', () {
      final report = PackageReport(packageDir: '/repo', command: 'dart')
        ..skippedPrerelease = 1
        ..heldBack.add(_held('equatable'));
      final output = StringBuffer();

      final exitCode = printReport([report], dryRun: false, output: output);

      final text = output.toString();
      expect(exitCode, 0);
      expect(text, contains('Held back (1)'));
      expect(text, contains('Skipped  1 prerelease-only'));
    });

    test('lists each package and sums totals for several packages', () {
      final output = StringBuffer();

      final exitCode = printReport(
        [
          PackageReport(packageDir: '/repo/a', command: 'dart')..changed = 2,
          PackageReport(packageDir: '/repo/b', command: 'dart')
            ..changed = 1
            ..failed = 1
            ..failures.add('http: version solving failed'),
        ],
        dryRun: false,
        output: output,
      );

      final text = output.toString();
      expect(exitCode, 1);
      expect(text, contains('  /repo/a: updated 2, failed 0\n'));
      expect(text, contains('  /repo/b: updated 1, failed 1\n'));
      expect(text, contains('  Updated  3\n'));
      expect(text, contains('  Failed   1\n'));
      expect(text, contains('  http:\n    version solving failed'));
    });

    test('ends with the dry-run notice in dry-run mode', () {
      final output = StringBuffer();

      printReport(
        [PackageReport(packageDir: '/repo', command: 'dart')..changed = 1],
        dryRun: true,
        output: output,
      );

      final text = output.toString();
      expect(text, isNot(contains('/repo: updated')));
      expect(text, endsWith('\nDry-run mode: no files were changed.\n'));
    });
  });
}
