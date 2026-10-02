import 'dart:convert';
import 'dart:io';

import 'package:pubup/src/sdk_resolver.dart';

/// Skip reason for tests that run [FakeSdk]'s POSIX shell scripts.
final Object fakeSdkSkip =
    Platform.isWindows ? 'FakeSdk uses POSIX shell scripts' : false;

/// A Flutter/Dart SDK stand-in whose `bin/dart` and `bin/flutter` are shell
/// scripts, so tests can drive pubup's real `Process.run` calls.
///
/// Every invocation is recorded in [calls]. Responses are keyed by the pub
/// subcommand (`outdated`, `add`, `get`) or, for other calls, by the first
/// argument (e.g. `--version`). Unconfigured calls succeed silently.
class FakeSdk {
  FakeSdk._(this.root);

  /// Creates the fake SDK in a new `fake_sdk` folder inside [parent].
  factory FakeSdk.create(Directory parent) {
    final sdk = FakeSdk._(Directory('${parent.path}/fake_sdk'));
    Directory('${sdk.root.path}/responses').createSync(recursive: true);
    Directory('${sdk.root.path}/bin').createSync();
    for (final name in const ['dart', 'flutter']) {
      final script = File('${sdk.root.path}/bin/$name')
        ..writeAsStringSync(_script(sdk.root.path));
      Process.runSync('chmod', ['+x', script.path]);
    }
    return sdk;
  }

  /// The SDK root, containing `bin/`.
  final Directory root;

  /// This SDK as pubup sees it after `--sdk <root>`.
  PubSdk get pubSdk => PubSdk.at(root.path, origin: 'fake');

  /// Answers calls for [key] with the given output and exit code.
  void respond(
    String key, {
    String stdout = '',
    String stderr = '',
    int exitCode = 0,
  }) {
    _response(key, 'stdout').writeAsStringSync(stdout);
    _response(key, 'stderr').writeAsStringSync(stderr);
    _response(key, 'exit').writeAsStringSync('$exitCode');
  }

  /// Fails calls for [key] with exit code 1 when an argument contains
  /// [argument].
  void failWhenArgumentContains(
    String key,
    String argument, {
    String stdout = '',
    String stderr = '',
  }) {
    _response(key, 'fail_on').writeAsStringSync(argument);
    _response(key, 'fail_stdout').writeAsStringSync(stdout);
    _response(key, 'fail_stderr').writeAsStringSync(stderr);
  }

  /// Recorded invocations, oldest first.
  List<FakeSdkCall> get calls {
    final log = File('${root.path}/calls.log');
    if (!log.existsSync()) return const [];
    return log.readAsLinesSync().map(FakeSdkCall._parse).toList();
  }

  File _response(String key, String kind) =>
      File('${root.path}/responses/$key.$kind');

  static String _script(String root) => '''
#!/bin/sh
root='$root'
echo "\$(basename "\$0")|\$(pwd -P)|\$*" >> "\$root/calls.log"
if [ "\$1" = "pub" ]; then key="\$2"; else key="\$1"; fi
response="\$root/responses/\$key"
if [ -f "\$response.fail_on" ]; then
  pattern=\$(cat "\$response.fail_on")
  for arg in "\$@"; do
    case "\$arg" in
      *"\$pattern"*)
        cat "\$response.fail_stdout"
        cat "\$response.fail_stderr" >&2
        exit 1
        ;;
    esac
  done
fi
if [ -f "\$response.stdout" ]; then cat "\$response.stdout"; fi
if [ -f "\$response.stderr" ]; then cat "\$response.stderr" >&2; fi
if [ -f "\$response.exit" ]; then exit "\$(cat "\$response.exit")"; fi
exit 0
''';
}

/// One recorded [FakeSdk] invocation.
class FakeSdkCall {
  const FakeSdkCall(this.executable, this.workingDirectory, this.arguments);

  factory FakeSdkCall._parse(String line) {
    final parts = line.split('|');
    return FakeSdkCall(parts[0], parts[1], parts[2]);
  }

  /// `dart` or `flutter`.
  final String executable;

  /// The working directory with symlinks resolved.
  final String workingDirectory;

  /// The arguments, joined by spaces.
  final String arguments;

  @override
  String toString() => '$executable in $workingDirectory: $arguments';
}

/// `pub outdated --json` output listing [packages].
String outdatedJson(List<Map<String, Object?>> packages) =>
    jsonEncode({'packages': packages});

/// One `pub outdated --json` package row.
Map<String, Object?> outdatedRow(
  String name, {
  String kind = 'direct',
  required String current,
  required String resolvable,
  String? latest,
}) =>
    {
      'package': name,
      'kind': kind,
      'current': {'version': current},
      'resolvable': {'version': resolvable},
      'latest': {'version': latest ?? resolvable},
    };
