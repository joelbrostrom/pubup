import 'package:pubup/src/version.dart';
import 'package:test/test.dart';

void main() {
  test('packageVersion matches pubspec release', () {
    expect(packageVersion, '0.2.1');
  });
}
