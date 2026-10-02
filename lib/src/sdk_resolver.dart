import 'dart:convert';
import 'dart:io';

/// Thrown when the SDK requested with `--sdk` cannot be used.
class SdkResolutionException implements Exception {
  /// Creates an [SdkResolutionException].
  SdkResolutionException(this.message);

  /// A human-readable explanation.
  final String message;

  @override
  String toString() => message;
}

/// The SDK whose `flutter` and `dart` executables pubup runs `pub` with.
class PubSdk {
  /// Uses `flutter` and `dart` from `PATH`.
  const PubSdk.fromPath()
      : root = null,
        origin = 'PATH';

  /// Uses the Flutter or Dart SDK at [root], the directory containing `bin/`.
  const PubSdk.at(String this.root, {required this.origin});

  /// The SDK root, or `null` when executables come from `PATH`.
  final String? root;

  /// Where the SDK came from, e.g. `PATH`, `FVM .fvm/versions/3.38.5`, or
  /// `--sdk /opt/flutter`.
  final String origin;

  /// Returns the executable to run for [command] (`"flutter"` or `"dart"`).
  ///
  /// [isWindows] defaults to the host platform.
  String executable(String command, {bool? isWindows}) {
    final sdkRoot = root;
    if (sdkRoot == null) return command;

    final bin = '$sdkRoot/bin/$command';
    if (!(isWindows ?? Platform.isWindows)) return bin;
    return File('$bin.exe').existsSync() ? '$bin.exe' : '$bin.bat';
  }
}

/// Picks the SDK pubup runs `pub` with.
///
/// Order of precedence:
///
/// 1. [sdkPath], from `--sdk`.
/// 2. The FVM pin in `<repoRoot>/.fvmrc`, linked at
///    `<repoRoot>/.fvm/versions/<version>`.
/// 3. The legacy FVM link `<repoRoot>/.fvm/flutter_sdk`.
/// 4. `flutter` and `dart` from `PATH`.
///
/// When `.fvmrc` pins a version that is not linked under `.fvm/versions/`,
/// a warning is written to [warnings] and `PATH` is used.
///
/// Throws [SdkResolutionException] when [sdkPath] has no `bin/dart`.
PubSdk resolvePubSdk({
  required Directory repoRoot,
  String? sdkPath,
  StringSink? warnings,
}) {
  if (sdkPath != null) {
    final root = Directory(sdkPath).absolute.path;
    if (!_hasExecutable(root, 'dart')) {
      throw SdkResolutionException(
        '--sdk $sdkPath is not a Flutter or Dart SDK (no bin/dart found).',
      );
    }
    return PubSdk.at(root, origin: '--sdk $sdkPath');
  }

  final fvmrc = File('${repoRoot.path}/.fvmrc');
  if (fvmrc.existsSync()) {
    final version = _fvmrcFlutterVersion(fvmrc);
    if (version != null) {
      final relative = '.fvm/versions/$version';
      final linked = '${repoRoot.path}/$relative';
      if (_hasExecutable(linked, 'flutter')) {
        return PubSdk.at(linked, origin: 'FVM $relative');
      }
      warnings?.writeln(
        '  ! .fvmrc pins Flutter $version, but $relative is missing. '
        'Run `fvm use $version` to link it. Using flutter from PATH.',
      );
      return const PubSdk.fromPath();
    }
  }

  final legacy = '${repoRoot.path}/.fvm/flutter_sdk';
  if (_hasExecutable(legacy, 'flutter')) {
    return PubSdk.at(legacy, origin: 'FVM .fvm/flutter_sdk');
  }

  return const PubSdk.fromPath();
}

/// Runs a version command such as `flutter --version --machine`.
typedef VersionCommandRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Returns the `SDK:` header line, e.g.
/// `SDK: Flutter 3.38.5, Dart 3.10.4 (FVM .fvm/versions/3.38.5)`.
///
/// [command] is the root package's pub command (`"flutter"` or `"dart"`).
/// Never throws: when the version cannot be read, the line says
/// `unknown version`.
Future<String> describeSdk({
  required PubSdk sdk,
  required String command,
  VersionCommandRunner? run,
}) async {
  final runner = run ?? (executable, args) => Process.run(executable, args);

  SdkVersion? version;
  try {
    if (command == 'flutter') {
      final result = await runner(sdk.executable('flutter'), [
        '--version',
        '--machine',
      ]);
      if (result.exitCode == 0) {
        version = parseFlutterVersionOutput(result.stdout as String);
      }
    } else {
      final result = await runner(sdk.executable('dart'), ['--version']);
      if (result.exitCode == 0) {
        version = parseDartVersionOutput('${result.stdout}\n${result.stderr}');
      }
    }
  } on Exception {
    version = null;
  }

  final described = version?.describe() ?? 'unknown version';
  final flutterRoot = version?.flutterRoot;
  final location = sdk.root == null && flutterRoot != null
      ? 'PATH: $flutterRoot'
      : sdk.origin;
  return 'SDK: $described ($location)';
}

/// SDK versions read from `flutter --version --machine` or `dart --version`.
class SdkVersion {
  /// Creates an [SdkVersion].
  const SdkVersion({this.flutter, this.dart, this.flutterRoot});

  /// The Flutter framework version, or `null` for a Dart-only SDK.
  final String? flutter;

  /// The Dart SDK version.
  final String? dart;

  /// The Flutter SDK directory reported by Flutter itself.
  final String? flutterRoot;

  /// Returns e.g. `Flutter 3.38.5, Dart 3.10.4`.
  String describe() => [
        if (flutter != null) 'Flutter $flutter',
        if (dart != null) 'Dart $dart',
      ].join(', ');
}

/// Parses the JSON printed by `flutter --version --machine`.
///
/// Tolerates text around the JSON object (e.g. upgrade banners). Returns
/// `null` when no Flutter version is present.
SdkVersion? parseFlutterVersionOutput(String stdout) {
  final start = stdout.indexOf('{');
  final end = stdout.lastIndexOf('}');
  if (start < 0 || end <= start) return null;

  final Object? json;
  try {
    json = jsonDecode(stdout.substring(start, end + 1));
  } on FormatException {
    return null;
  }
  if (json is! Map<String, dynamic>) return null;

  final flutter = json['frameworkVersion'] ?? json['flutterVersion'];
  if (flutter is! String) return null;

  final dart = json['dartSdkVersion'];
  final root = json['flutterRoot'];
  return SdkVersion(
    flutter: flutter,
    // Pre-release Dart SDKs report e.g. `3.14.0 (build 3.14.0-211.1.beta)`.
    dart: dart is String ? dart.split(' ').first : null,
    flutterRoot: root is String ? root : null,
  );
}

/// Parses `dart --version` output, e.g.
/// `Dart SDK version: 3.10.4 (stable) (...) on "macos_arm64"`.
SdkVersion? parseDartVersionOutput(String output) {
  final match = RegExp(r'Dart SDK version: (\S+)').firstMatch(output);
  if (match == null) return null;
  return SdkVersion(dart: match.group(1));
}

String? _fvmrcFlutterVersion(File fvmrc) {
  try {
    final json = jsonDecode(fvmrc.readAsStringSync());
    if (json is! Map<String, dynamic>) return null;
    final version = json['flutter'];
    if (version is! String || version.trim().isEmpty) return null;
    return version.trim();
  } on FormatException {
    return null;
  }
}

bool _hasExecutable(String sdkRoot, String command) {
  final bin = '$sdkRoot/bin/$command';
  return File(bin).existsSync() ||
      File('$bin.bat').existsSync() ||
      File('$bin.exe').existsSync();
}
