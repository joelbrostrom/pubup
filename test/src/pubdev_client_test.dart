import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pubup/src/pubdev_client.dart';
import 'package:test/test.dart';

void main() {
  group('PubDevClient.getVersions', () {
    test('hits the expected pub.dev URL', () async {
      Uri? capturedUri;

      final mock = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({
            'name': 'foo',
            'latest': {'version': '1.2.3'},
            'versions': [
              {'version': '1.0.0'},
              {'version': '1.2.3'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = PubDevClient(httpClient: mock);
      await client.getVersions('foo');

      expect(capturedUri, Uri.parse('https://pub.dev/api/packages/foo'));
    });

    test('parses the versions array preserving order', () async {
      final mock = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'name': 'args',
            'versions': [
              {'version': '0.1.0'},
              {'version': '1.0.0'},
              {'version': '2.7.0'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = PubDevClient(httpClient: mock);
      final versions = await client.getVersions('args');
      expect(versions, ['0.1.0', '1.0.0', '2.7.0']);
    });

    test('skips entries that are not maps or have no version string',
        () async {
      final mock = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'versions': [
              {'version': '1.0.0'},
              {'not_version': 'oops'},
              'plain string',
              {'version': '2.0.0'},
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = PubDevClient(httpClient: mock);
      final versions = await client.getVersions('foo');
      expect(versions, ['1.0.0', '2.0.0']);
    });

    test('throws PubDevRequestFailure for non-200 responses', () async {
      final mock = MockClient((_) async => http.Response('not found', 404));
      final client = PubDevClient(httpClient: mock);

      await expectLater(
        client.getVersions('missing'),
        throwsA(
          isA<PubDevRequestFailure>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.packageName, 'packageName', 'missing'),
        ),
      );
    });

    test('throws PubDevResponseFormatException for malformed JSON', () async {
      final mock = MockClient(
        (_) async => http.Response('this is not json', 200),
      );
      final client = PubDevClient(httpClient: mock);

      await expectLater(
        client.getVersions('foo'),
        throwsA(isA<PubDevResponseFormatException>()),
      );
    });

    test('throws PubDevResponseFormatException when versions is missing',
        () async {
      final mock = MockClient((_) async {
        return http.Response(
          jsonEncode({'name': 'foo'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final client = PubDevClient(httpClient: mock);

      await expectLater(
        client.getVersions('foo'),
        throwsA(isA<PubDevResponseFormatException>()),
      );
    });

    test('honours custom baseUrl', () async {
      Uri? capturedUri;
      final mock = MockClient((request) async {
        capturedUri = request.url;
        return http.Response(
          jsonEncode({'versions': <Map<String, String>>[]}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final client = PubDevClient(
        httpClient: mock,
        baseUrl: 'https://example.test',
      );
      await client.getVersions('foo');

      expect(capturedUri, Uri.parse('https://example.test/api/packages/foo'));
    });
  });
}
