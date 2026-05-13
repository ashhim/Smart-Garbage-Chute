import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiService extends ChangeNotifier {
  ApiService({
    String? apiBaseUrl,
    String? websocketUrl,
  })  : _defaultApiBaseUrl = _normalizeApiBaseUrl(
          apiBaseUrl ?? _resolveDefaultApiBaseUrl(),
        ),
        _defaultWebSocketUrl = websocketUrl ??
            _deriveWebSocketUrl(apiBaseUrl ?? _resolveDefaultApiBaseUrl()),
        _apiBaseUrl = _normalizeApiBaseUrl(apiBaseUrl ?? _resolveDefaultApiBaseUrl()),
        _websocketUrl =
            websocketUrl ?? _deriveWebSocketUrl(apiBaseUrl ?? _resolveDefaultApiBaseUrl());

  static const _apiBaseKey = 'api_base_url';
  static const _webSocketKey = 'ws_url';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final String _defaultApiBaseUrl;
  final String _defaultWebSocketUrl;

  String _apiBaseUrl;
  String _websocketUrl;
  String? _token;

  String get apiBaseUrl => _apiBaseUrl;
  String get websocketUrl => _websocketUrl;
  String get defaultApiBaseUrl => _defaultApiBaseUrl;

  Future<void> initialize() async {
    final savedApiBaseUrl = await _storage.read(key: _apiBaseKey);
    final savedWebSocketUrl = await _storage.read(key: _webSocketKey);

    if (savedApiBaseUrl != null && savedApiBaseUrl.trim().isNotEmpty) {
      _apiBaseUrl = _normalizeApiBaseUrl(savedApiBaseUrl);
      _websocketUrl = savedWebSocketUrl != null && savedWebSocketUrl.isNotEmpty
          ? savedWebSocketUrl
          : _deriveWebSocketUrl(_apiBaseUrl);
      return;
    }

    _apiBaseUrl = _defaultApiBaseUrl;
    _websocketUrl = _defaultWebSocketUrl;
  }

  Future<void> configureBaseUrl(String rawValue) async {
    final normalizedApiBaseUrl = _normalizeApiBaseUrl(rawValue);
    _apiBaseUrl = normalizedApiBaseUrl;
    _websocketUrl = _deriveWebSocketUrl(normalizedApiBaseUrl);

    await _storage.write(key: _apiBaseKey, value: _apiBaseUrl);
    await _storage.write(key: _webSocketKey, value: _websocketUrl);
    notifyListeners();
  }

  Future<void> resetBaseUrl() async {
    _apiBaseUrl = _defaultApiBaseUrl;
    _websocketUrl = _defaultWebSocketUrl;

    await _storage.delete(key: _apiBaseKey);
    await _storage.delete(key: _webSocketKey);
    notifyListeners();
  }

  void setToken(String? token) {
    _token = token;
  }

  Future<dynamic> get(String endpoint) async {
    final response = await http.get(
      _buildUri(endpoint),
      headers: _headers(),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> post(String endpoint, [Object? body]) async {
    final response = await http.post(
      _buildUri(endpoint),
      headers: _headers(),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> delete(String endpoint) async {
    final response = await http.delete(
      _buildUri(endpoint),
      headers: _headers(),
    );
    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> probe() async {
    return _probeBaseUrl(_apiBaseUrl);
  }

  Future<bool> isCurrentEndpointReachable() async {
    try {
      await _probeBaseUrl(_apiBaseUrl);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> discoverAndConfigure({bool includeLanDiscovery = true}) async {
    final detected = await _discoverReachableBaseUrl(
      includeLanDiscovery: includeLanDiscovery,
    );
    if (detected == null) {
      return false;
    }

    if (detected != _apiBaseUrl) {
      await configureBaseUrl(detected);
    }
    return true;
  }

  WebSocketChannel connectWebSocket() {
    final uri = Uri.parse(_websocketUrl);
    final wsUri = _token == null
        ? uri
        : uri.replace(
            queryParameters: {
              ...uri.queryParameters,
              'token': _token!,
            },
          );
    return WebSocketChannel.connect(wsUri);
  }

  List<Map<String, dynamic>> expectList(dynamic payload) {
    if (payload is List) {
      return payload
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }

    if (payload is Map && payload['items'] is List) {
      return (payload['items'] as List)
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
    }

    return const [];
  }

  Map<String, dynamic> expectMap(dynamic payload) {
    if (payload is Map<String, dynamic>) {
      return payload;
    }
    if (payload is Map) {
      return payload.cast<String, dynamic>();
    }
    throw ApiException('Unexpected response payload');
  }

  Uri _buildUri(String endpoint) {
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      return Uri.parse(endpoint);
    }

    return _buildUriForBase(_apiBaseUrl, endpoint);
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  dynamic _decodeResponse(http.Response response) {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    if (response.statusCode == 401) {
      throw UnauthorizedException(_extractError(body, response.statusCode));
    }

    throw ApiException(_extractError(body, response.statusCode));
  }

  String _extractError(dynamic body, int statusCode) {
    if (body is Map && body['detail'] != null) {
      return body['detail'].toString();
    }
    return 'HTTP $statusCode';
  }

  Future<Map<String, dynamic>> _probeBaseUrl(String baseUrl) async {
    final response = await http
        .get(
          _buildUriForBase(baseUrl, '/health'),
          headers: const {'Content-Type': 'application/json'},
        )
        .timeout(const Duration(milliseconds: 1200));

    final payload = response.body.isEmpty
        ? const <String, dynamic>{}
        : expectMap(jsonDecode(response.body));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(_extractError(payload, response.statusCode));
    }

    return payload;
  }

  Future<String?> _discoverReachableBaseUrl({
    required bool includeLanDiscovery,
  }) async {
    final detectedFromKnown =
        await _probeCandidates(_candidateBaseUrls(), timeout: const Duration(milliseconds: 900));
    if (detectedFromKnown != null) {
      return detectedFromKnown;
    }

    if (!includeLanDiscovery) {
      return null;
    }

    return _discoverLanBaseUrl();
  }

  Future<String?> _probeCandidates(
    List<String> candidates, {
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    final uniqueCandidates = <String>{};
    final normalizedCandidates = <String>[];
    for (final candidate in candidates) {
      final normalized = _normalizeApiBaseUrl(candidate);
      if (uniqueCandidates.add(normalized)) {
        normalizedCandidates.add(normalized);
      }
    }

    for (final candidate in normalizedCandidates) {
      try {
        await http
            .get(
              _buildUriForBase(candidate, '/health'),
              headers: const {'Content-Type': 'application/json'},
            )
            .timeout(timeout);
        return candidate;
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  Future<String?> _discoverLanBaseUrl() async {
    try {
      final privateInterfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      final prefixes = <String>{};
      final ownAddresses = <String>{};

      for (final interface in privateInterfaces) {
        for (final address in interface.addresses) {
          if (!_isPrivateIpv4(address.address)) {
            continue;
          }
          ownAddresses.add(address.address);
          final parts = address.address.split('.');
          if (parts.length == 4) {
            prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
          }
        }
      }

      final hostCandidates = <String>[];
      const preferredOctets = <int>[1, 2, 10, 20, 50, 100, 101, 110, 150, 200];
      for (final prefix in prefixes) {
        final orderedOctets = <int>[
          ...preferredOctets,
          ...List.generate(254, (index) => index + 1)
              .where((octet) => !preferredOctets.contains(octet)),
        ];
        for (final octet in orderedOctets) {
          final host = '$prefix.$octet';
          if (ownAddresses.contains(host)) {
            continue;
          }
          hostCandidates.add('http://$host/api');
          hostCandidates.add('http://$host:8520/api');
        }
      }

      return _probeCandidates(
        hostCandidates,
        timeout: const Duration(milliseconds: 350),
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _candidateBaseUrls() {
    final candidates = <String>[
      _apiBaseUrl,
      _defaultApiBaseUrl,
    ];

    if (Platform.isAndroid) {
      candidates.addAll(const [
        'http://10.0.2.2/api',
        'http://10.0.2.2:8520/api',
      ]);
    }

    candidates.addAll(const [
      'http://127.0.0.1/api',
      'http://127.0.0.1:8520/api',
      'http://localhost/api',
      'http://localhost:8520/api',
    ]);

    return candidates;
  }

  static bool _isPrivateIpv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) {
      return false;
    }

    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == null || second == null) {
      return false;
    }

    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  static Uri _buildUriForBase(String baseUrl, String endpoint) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return Uri.parse('$normalizedBase$normalizedEndpoint');
  }

  static String _resolveDefaultApiBaseUrl() {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) {
      return _normalizeApiBaseUrl(defined);
    }

    if (Platform.isAndroid) {
      return 'http://10.0.2.2/api';
    }

    return 'http://127.0.0.1/api';
  }

  static String _normalizeApiBaseUrl(String rawValue) {
    var value = _sanitizeRawValue(rawValue);
    if (value.isEmpty) {
      value = _resolveDefaultApiBaseUrl();
    }

    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }

    final uri = Uri.parse(value);
    final pathSegments =
        uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (pathSegments.isEmpty || pathSegments.last != 'api') {
      pathSegments.add('api');
    }

    return uri
        .replace(pathSegments: pathSegments, queryParameters: const {})
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }

  static String _sanitizeRawValue(String rawValue) {
    var value = rawValue.trim();
    if (value.isEmpty) {
      return value;
    }

    final queryIndex = value.indexOf('?');
    if (queryIndex >= 0) {
      value = value.substring(0, queryIndex);
    }
    final fragmentIndex = value.indexOf('#');
    if (fragmentIndex >= 0) {
      value = value.substring(0, fragmentIndex);
    }

    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  static String _deriveWebSocketUrl(String apiBaseUrl) {
    final normalizedApiBaseUrl = _normalizeApiBaseUrl(apiBaseUrl);
    final apiUri = Uri.parse(normalizedApiBaseUrl);
    final pathSegments =
        apiUri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (pathSegments.isNotEmpty && pathSegments.last == 'api') {
      pathSegments.removeLast();
    }
    pathSegments.add('ws');

    return apiUri
        .replace(
          scheme: apiUri.scheme == 'https' ? 'wss' : 'ws',
          pathSegments: pathSegments,
          queryParameters: const {},
        )
        .toString();
  }
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class UnauthorizedException extends ApiException {
  UnauthorizedException(super.message);
}
