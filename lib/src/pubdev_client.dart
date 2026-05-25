import 'dart:convert';

import 'package:http/http.dart' as http;

/// Default base URL for pub.dev's package API.
const _defaultBaseUrl = 'https://pub.dev';

/// Path used to query package version metadata.
const _packagesPath = '/api/packages/';

/// Thrown when the pub.dev API request returns a non-200 status code.
class PubDevRequestFailure implements Exception {
  /// Creates a [PubDevRequestFailure].
  PubDevRequestFailure(this.statusCode, this.packageName);

  /// The HTTP status code returned by pub.dev.
  final int statusCode;

  /// The package name that was being looked up.
  final String packageName;

  @override
  String toString() =>
      'PubDevRequestFailure: $packageName returned HTTP $statusCode';
}

/// Thrown when the pub.dev API response cannot be parsed.
class PubDevResponseFormatException implements Exception {
  /// Creates a [PubDevResponseFormatException].
  PubDevResponseFormatException(this.packageName, [this.cause]);

  /// The package name that was being looked up.
  final String packageName;

  /// The underlying cause, if any.
  final Object? cause;

  @override
  String toString() =>
      'PubDevResponseFormatException: could not parse response for '
      '$packageName${cause != null ? ' ($cause)' : ''}';
}

/// Thin client around `https://pub.dev/api/packages/<name>` for fetching the
/// list of published versions.
///
/// `pub_updater` only exposes the latest version; pubup needs the full list
/// so it can pick the highest version that fits the user-selected bump
/// level (`--bump <major|minor|patch>`).
class PubDevClient {
  /// Creates a [PubDevClient].
  ///
  /// Pass an [httpClient] to inject a mock for tests. A custom [baseUrl] can
  /// also be supplied for tests.
  PubDevClient({http.Client? httpClient, String baseUrl = _defaultBaseUrl})
      : _client = httpClient ?? http.Client(),
        _baseUrl = baseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Returns all published version strings of [packageName] in the order
  /// pub.dev reports them.
  ///
  /// Throws [PubDevRequestFailure] for non-200 responses and
  /// [PubDevResponseFormatException] when the response body cannot be parsed.
  Future<List<String>> getVersions(String packageName) async {
    final uri = Uri.parse('$_baseUrl$_packagesPath$packageName');
    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw PubDevRequestFailure(response.statusCode, packageName);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (e) {
      throw PubDevResponseFormatException(packageName, e);
    }

    if (decoded is! Map<String, dynamic>) {
      throw PubDevResponseFormatException(packageName);
    }

    final versions = decoded['versions'];
    if (versions is! List) {
      throw PubDevResponseFormatException(packageName);
    }

    final result = <String>[];
    for (final entry in versions) {
      if (entry is! Map) continue;
      final version = entry['version'];
      if (version is String) result.add(version);
    }
    return result;
  }

  /// Closes the underlying HTTP client.
  void close() => _client.close();
}
