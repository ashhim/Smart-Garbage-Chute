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
          apiBaseUrl ?? _resolveApiBaseUrl(),
        ),
        _defaultWebSocketUrl =
            websocketUrl ?? _deriveWebSocketUrl(apiBaseUrl ?? _resolveApiBaseUrl()),
        _apiBaseUrl = _normalizeApiBaseUrl(apiBaseUrl ?? _resolveApiBaseUrl()),
        _websocketUrl =
            websocketUrl ?? _deriveWebSocketUrl(apiBaseUrl ?? _resolveApiBaseUrl());

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
    } else {
      _apiBaseUrl = _defaultApiBaseUrl;
      _websocketUrl = _defaultWebSocketUrl;
    }
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
    final payload = await get('/health');
    return expectMap(payload);
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

    final normalizedBase = _apiBaseUrl.endsWith('/')
        ? _apiBaseUrl.substring(0, _apiBaseUrl.length - 1)
        : _apiBaseUrl;
    final normalizedEndpoint =
        endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return Uri.parse('$normalizedBase$normalizedEndpoint');
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

  static String _resolveApiBaseUrl() {
    const defined = String.fromEnvironment('API_BASE_URL');
    if (defined.isNotEmpty) {
      return _normalizeApiBaseUrl(defined);
    }

    if (Platform.isAndroid) {
      return 'http://10.0.2.2:8520/api';
    }

    return 'http://127.0.0.1:8520/api';
  }

  static String _normalizeApiBaseUrl(String rawValue) {
    var value = rawValue.trim();
    if (value.isEmpty) {
      value = _resolveApiBaseUrl();
    }

    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }

    final uri = Uri.parse(value);
    final pathSegments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList();
    if (pathSegments.isEmpty || pathSegments.last != 'api') {
      pathSegments.add('api');
    }

    return uri
        .replace(pathSegments: pathSegments, queryParameters: const {})
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }

  static String _deriveWebSocketUrl(String apiBaseUrl) {
    final normalizedApiBaseUrl = _normalizeApiBaseUrl(apiBaseUrl);
    final apiUri = Uri.parse(normalizedApiBaseUrl);
    final pathSegments = apiUri.pathSegments.where((segment) => segment.isNotEmpty).toList();
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
