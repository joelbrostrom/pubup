import 'dart:io';

import 'package:pubup/src/version.dart';
import 'package:test/test.dart';

void main() {
  Future<ProcessResult> pubup(List<String> arguments) => Process.run(
        Platform.resolvedExecutable,
        ['bin/pubup.dart', ...arguments],
        environment: const {'CI': 'true'},
      );

  test('prints the version and exits with 0', () async {
    final result = await pubup(['--version']);

    expect(result.stdout, 'pubup $packageVersion\n');
    expect(result.exitCode, 0);
  });

  test('exits with the CLI exit code', () async {
    final result = await pubup(['--bogus']);

    expect(result.stderr, contains('Could not find an option named'));
    expect(result.exitCode, 64);
  });
}
