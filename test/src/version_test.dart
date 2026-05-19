import 'dart:io';

import 'package:pubup/src/version.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('packageVersion matches version in pubspec.yaml', () {
    final pubspec =
        loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    final pubspecVersion = pubspec['version'] as String;

    expect(
      packageVersion,
      pubspecVersion,
      reason: 'lib/src/version.dart must stay in sync with pubspec.yaml. '
          'Bump both together when cutting a release.',
    );
  });
}
