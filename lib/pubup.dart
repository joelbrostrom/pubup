/// A CLI tool that updates pubspec.yaml dependency constraints to the latest
/// resolvable versions across Dart and Flutter workspace packages.
///
/// ## Quick start
///
/// ```bash
/// dart pub global activate pubup
/// pubup --dry-run
/// ```
///
/// See the [README](https://pub.dev/packages/pubup) for full usage.
library;

export 'src/candidate_collector.dart'
    show CandidateUpdate, CollectionReport, CollectionResult, collectCandidates;
export 'src/outdated_runner.dart' show OutdatedPackage, getOutdatedPackages;
export 'src/pubspec_parser.dart'
    show
        DependencyEntry,
        PubspecDependencies,
        isFlutterPackage,
        parseDependencyEntries;
export 'src/reporter.dart' show PackageReport, printReport;
export 'src/updater.dart' show runUpdatesForPackage;
export 'src/workspace_discovery.dart' show discoverWorkspaceDirs, filterTargets;
