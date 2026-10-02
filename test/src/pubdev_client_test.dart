import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pubup/src/pubdev_client.dart';
import 'package:test/test.dart';

class _TrackingClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}

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

    test('skips entries that are not maps or have no version string', () async {
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

    test('throws PubDevResponseFormatException when the body is not an object',
        () async {
      final mock = MockClient((_) async => http.Response('[]', 200));
      final client = PubDevClient(httpClient: mock);

      await expectLater(
        client.getVersions('foo'),
        throwsA(
          isA<PubDevResponseFormatException>()
              .having((e) => e.cause, 'cause', isNull),
        ),
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

    test('fetches over HTTP with its own client when none is injected',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) {
        request.response
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'versions': [
                {'version': request.uri.path},
              ],
            }),
          )
          ..close();
      });

      final client = PubDevClient(baseUrl: 'http://127.0.0.1:${server.port}');
      addTearDown(client.close);

      expect(await client.getVersions('foo'), ['/api/packages/foo']);
    });
  });

  group('PubDevClient.close', () {
    test('closes the injected HTTP client', () {
      final httpClient = _TrackingClient();

      PubDevClient(httpClient: httpClient).close();

      expect(httpClient.closed, isTrue);
    });
  });

  group('exceptions', () {
    test('PubDevRequestFailure names the package and status code', () {
      expect(
        PubDevRequestFailure(503, 'http').toString(),
        'PubDevRequestFailure: http returned HTTP 503',
      );
    });

    test('PubDevResponseFormatException includes the cause when known', () {
      expect(
        PubDevResponseFormatException('http').toString(),
        'PubDevResponseFormatException: could not parse response for http',
      );
      expect(
        PubDevResponseFormatException('http', 'bad json').toString(),
        'PubDevResponseFormatException: could not parse response for http '
        '(bad json)',
      );
    });
  });
}
