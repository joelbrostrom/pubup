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
export 'src/commands/self_update.dart' show runSelfUpdate;
export 'src/constraint_rewriter.dart'
    show RewriteResult, rewriteConstraint, standardConstraintPattern;
export 'src/outdated_runner.dart' show OutdatedPackage, getOutdatedPackages;
export 'src/pubdev_client.dart'
    show PubDevClient, PubDevRequestFailure, PubDevResponseFormatException;
export 'src/pubspec_parser.dart'
    show
        DependencyEntry,
        PubspecDependencies,
        isFlutterPackage,
        parseDependencyEntries;
export 'src/reporter.dart'
    show PackageReport, WorkspaceReport, printReport, printWorkspaceReport;
export 'src/status_line.dart'
    show StatusLine, StatusReporter, disableProgressEnv, noopStatusReporter;
export 'src/update_checker.dart'
    show
        checkForUpdate,
        disableUpdateCheckEnv,
        isUpdateCheckDisabled,
        pubupPackageName,
        resolveUpdateCacheDir;
export 'src/updater.dart' show runUpdatesForPackage;
export 'src/version.dart' show packageVersion;
export 'src/version_resolver.dart'
    show
        BumpLevel,
        VersionsFetcher,
        bumpLevelFromString,
        pickTargetVersion,
        versionFitsBound;
export 'src/workspace_discovery.dart' show discoverWorkspaceDirs, filterTargets;
export 'src/workspace_mode.dart'
    show isWorkspaceRoot, isWorkspaceRootFromString;
export 'src/workspace_updater.dart'
    show
        OutdatedPackagesFetcher,
        PubGetRunner,
        WorkspaceMemberCandidate,
        runUpdatesForWorkspace;
