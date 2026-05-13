import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiService {
  ApiService({
    String? apiBaseUrl,
    String? websocketUrl,
  })  : _apiBaseUrl = apiBaseUrl ?? _resolveApiBaseUrl(),
        _websocketUrl = websocketUrl ?? _resolveWebSocketUrl();

  final String _apiBaseUrl;
  final String _websocketUrl;
  String? _token;

  String get apiBaseUrl => _apiBaseUrl;
  String get websocketUrl => _websocketUrl;

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

  WebSocketChannel connectWebSocket() {
    final uri = Uri.parse(_websocketUrl);
    final wsUri = _token == null
        ? uri
        : uri.replace(queryParameters: {
            ...uri.queryParameters,
            'token': _token!,
          });
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
      return defined;
    }

    if (Platform.isAndroid) {
      return 'http://10.0.2.2/api';
    }

    return 'http://localhost/api';
  }

  static String _resolveWebSocketUrl() {
    const defined = String.fromEnvironment('WS_URL');
    if (defined.isNotEmpty) {
      return defined;
    }

    if (Platform.isAndroid) {
      return 'ws://10.0.2.2/ws';
    }

    return 'ws://localhost/ws';
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
