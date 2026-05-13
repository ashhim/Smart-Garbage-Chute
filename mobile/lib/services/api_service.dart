import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiService extends ChangeNotifier {
  ApiService({String? apiBaseUrlOverride})
      : _buildOverrideConfig = _parseBuildOverride(apiBaseUrlOverride);

  static const apiBaseStorageKey = 'api_base_url';
  static const webSocketStorageKey = 'ws_url';
  static const _serverHostKey = 'server_host';
  static const _serverPortKey = 'server_port';
  static const _serverHttpsKey = 'server_https';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final ServerConnectionConfig? _buildOverrideConfig;

  ServerConnectionConfig? _connectionConfig;
  String _apiBaseUrl = '';
  String _websocketUrl = '';
  String? _token;

  String get apiBaseUrl => _apiBaseUrl;
  String get websocketUrl => _websocketUrl;
  String get serverDisplayName =>
      _connectionConfig?.displayLabel ?? 'Server not configured';
  String get serverHost => _connectionConfig?.host ?? '';
  String get serverPort => _connectionConfig?.port?.toString() ?? '';
  bool get useHttps => _connectionConfig?.useHttps ?? false;
  bool get hasConnectionConfig => _connectionConfig != null;
  bool get usesBuildOverride => _buildOverrideConfig != null;

  Future<void> initialize() async {
    final buildOverride = _buildOverrideConfig;
    if (buildOverride != null) {
      _applyConfig(buildOverride);
      return;
    }

    final savedHost = await _storage.read(key: _serverHostKey);
    final savedPort = await _storage.read(key: _serverPortKey);
    final savedHttps = await _storage.read(key: _serverHttpsKey);
    final savedApiBaseUrl = await _storage.read(key: apiBaseStorageKey);

    if (savedHost != null && savedHost.trim().isNotEmpty) {
      final port = int.tryParse(savedPort ?? '');
      final useHttps = savedHttps == 'true';
      _applyConfig(
        ServerConnectionConfig(
          host: savedHost.trim(),
          port: port,
          useHttps: useHttps,
        ),
      );
      return;
    }

    if (savedApiBaseUrl != null && savedApiBaseUrl.trim().isNotEmpty) {
      final migrated = ServerConnectionConfig.fromApiBaseUrl(savedApiBaseUrl);
      if (migrated != null) {
        _applyConfig(migrated);
        return;
      }
    }

    _connectionConfig = null;
    _apiBaseUrl = '';
    _websocketUrl = '';
  }

  Future<ConnectionValidationResult> validateAndConfigureConnection({
    required String hostInput,
    String? portInput,
    required bool useHttps,
  }) async {
    if (usesBuildOverride) {
      final override = _buildOverrideConfig!;
      final status = await _validateConnection(override);
      _applyConfig(override, notifyListenersAfterUpdate: true);
      return status;
    }

    final config = ServerConnectionConfig.fromUserInput(
      hostInput: hostInput,
      portInput: portInput,
      useHttps: useHttps,
    );
    final status = await _validateConnection(config);
    await _persistConfig(config);
    _applyConfig(config, notifyListenersAfterUpdate: true);
    return status;
  }

  Future<void> clearConnection() async {
    if (usesBuildOverride) {
      return;
    }

    _connectionConfig = null;
    _apiBaseUrl = '';
    _websocketUrl = '';
    _token = null;

    await _storage.delete(key: _serverHostKey);
    await _storage.delete(key: _serverPortKey);
    await _storage.delete(key: _serverHttpsKey);
    await _storage.delete(key: apiBaseStorageKey);
    await _storage.delete(key: webSocketStorageKey);
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
    final config = _requireConnectionConfig();
    return _healthCheck(config);
  }

  Future<bool> isCurrentEndpointReachable() async {
    final config = _connectionConfig;
    if (config == null) {
      return false;
    }

    try {
      await _healthCheck(config);
      return true;
    } catch (_) {
      return false;
    }
  }

  WebSocketChannel connectWebSocket() {
    if (_websocketUrl.isEmpty) {
      throw ConnectionConfigurationException(
        'Server connection is not configured.',
      );
    }

    final uri = Uri.parse(_websocketUrl);
    final wsUri = _token == null || _token!.isEmpty
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
    throw InvalidBackendResponseException(
      'The server returned an unexpected response format.',
    );
  }

  Uri _buildUri(String endpoint) {
    if (endpoint.startsWith('http://') || endpoint.startsWith('https://')) {
      return Uri.parse(endpoint);
    }

    final baseUrl = _requireConnectionConfig().apiBaseUrl;
    final normalizedEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return Uri.parse('$baseUrl$normalizedEndpoint');
  }

  Map<String, String> _headers() {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_token != null && _token!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_token';
    }
    return headers;
  }

  dynamic _decodeResponse(http.Response response) {
    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        body = response.body;
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    final message = _extractError(body, response.statusCode);
    if (response.statusCode == 401) {
      throw UnauthorizedException(message);
    }

    throw ApiException(message);
  }

  String _extractError(dynamic body, int statusCode) {
    if (body is Map && body['detail'] != null) {
      return body['detail'].toString();
    }
    if (body is String && body.trim().isNotEmpty) {
      return body;
    }
    return 'HTTP $statusCode';
  }

  Future<ConnectionValidationResult> _validateConnection(
    ServerConnectionConfig config,
  ) async {
    final health = await _healthCheck(config);
    await _verifyAuthEndpoint(config);
    return ConnectionValidationResult(
      serverDisplayName: config.displayLabel,
      apiBaseUrl: config.apiBaseUrl,
      healthStatus: health['status']?.toString() ?? 'ok',
    );
  }

  Future<Map<String, dynamic>> _healthCheck(
    ServerConnectionConfig config,
  ) async {
    late http.Response response;
    try {
      response = await http
          .get(
            config.apiUri('/health'),
            headers: const {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      throw ConnectionTimeoutException(
        'The server did not respond in time.',
      );
    } on SocketException {
      throw HostUnreachableException(
        'Unable to reach the selected server.',
      );
    } catch (_) {
      throw HostUnreachableException(
        'Unable to reach the selected server.',
      );
    }

    final payload = _safeDecodeMap(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw InvalidBackendResponseException(
        'The server responded, but the health check failed.',
      );
    }
    if (payload == null || payload['status'] == null) {
      throw InvalidBackendResponseException(
        'The server response does not match the monitoring backend.',
      );
    }
    return payload;
  }

  Future<void> _verifyAuthEndpoint(ServerConnectionConfig config) async {
    late http.Response response;
    try {
      response = await http
          .post(
            config.apiUri('/auth/login'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(
              const {
                'email': 'connection-check',
                'password': 'connection-check',
              },
            ),
          )
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      throw ConnectionTimeoutException(
        'The authentication service did not respond in time.',
      );
    } on SocketException {
      throw HostUnreachableException(
        'Unable to reach the selected server.',
      );
    } catch (_) {
      throw HostUnreachableException(
        'Unable to reach the selected server.',
      );
    }

    if (response.statusCode == 404) {
      throw AuthEndpointUnavailableException(
        'The server is reachable, but sign-in is unavailable.',
      );
    }
    if (response.statusCode >= 500) {
      throw AuthEndpointUnavailableException(
        'The server is reachable, but sign-in is unavailable.',
      );
    }
    if (response.statusCode == 200 ||
        response.statusCode == 400 ||
        response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.statusCode == 422) {
      return;
    }

    throw InvalidBackendResponseException(
      'The server does not expose the expected sign-in API.',
    );
  }

  Map<String, dynamic>? _safeDecodeMap(String rawBody) {
    if (rawBody.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  ServerConnectionConfig _requireConnectionConfig() {
    final config = _connectionConfig;
    if (config == null) {
      throw ConnectionConfigurationException(
        'Server connection is not configured.',
      );
    }
    return config;
  }

  Future<void> _persistConfig(ServerConnectionConfig config) async {
    await _storage.write(key: _serverHostKey, value: config.host);
    await _storage.write(
      key: _serverPortKey,
      value: config.port?.toString() ?? '',
    );
    await _storage.write(
      key: _serverHttpsKey,
      value: config.useHttps.toString(),
    );
    await _storage.write(key: apiBaseStorageKey, value: config.apiBaseUrl);
    await _storage.write(key: webSocketStorageKey, value: config.websocketUrl);
  }

  void _applyConfig(
    ServerConnectionConfig config, {
    bool notifyListenersAfterUpdate = false,
  }) {
    _connectionConfig = config;
    _apiBaseUrl = config.apiBaseUrl;
    _websocketUrl = config.websocketUrl;
    if (notifyListenersAfterUpdate) {
      notifyListeners();
    }
  }

  static ServerConnectionConfig? _parseBuildOverride(String? apiBaseOverride) {
    final rawValue = apiBaseOverride ?? const String.fromEnvironment('API_BASE_URL');
    if (rawValue.trim().isEmpty) {
      return null;
    }
    return ServerConnectionConfig.fromApiBaseUrl(rawValue.trim());
  }
}

class ServerConnectionConfig {
  const ServerConnectionConfig({
    required this.host,
    required this.useHttps,
    this.port,
  });

  final String host;
  final int? port;
  final bool useHttps;

  String get displayLabel => port == null ? host : '$host:$port';

  String get apiBaseUrl => _uriForPath('/api').toString();

  String get websocketUrl {
    final uri = _uriForPath('/ws');
    return uri
        .replace(scheme: useHttps ? 'wss' : 'ws')
        .toString();
  }

  Uri apiUri(String endpoint) {
    final normalizedEndpoint = endpoint.startsWith('/') ? endpoint : '/$endpoint';
    return Uri.parse('$apiBaseUrl$normalizedEndpoint');
  }

  factory ServerConnectionConfig.fromUserInput({
    required String hostInput,
    String? portInput,
    required bool useHttps,
  }) {
    final parsedHost = _parseHostInput(hostInput);
    final host = parsedHost.host.trim();
    if (host.isEmpty) {
      throw ConnectionConfigurationException(
        'Enter a server IP or host name.',
      );
    }

    int? port = parsedHost.port;
    final portValue = (portInput ?? '').trim();
    if (portValue.isNotEmpty) {
      port = int.tryParse(portValue);
      if (port == null || port < 1 || port > 65535) {
        throw ConnectionConfigurationException(
          'Enter a valid port number.',
        );
      }
    }

    return ServerConnectionConfig(
      host: host,
      port: port,
      useHttps: useHttps,
    );
  }

  static ServerConnectionConfig? fromApiBaseUrl(String rawValue) {
    final normalized = rawValue.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }

    final useHttps = uri.scheme.toLowerCase() == 'https';
    final port = uri.hasPort ? uri.port : null;
    return ServerConnectionConfig(
      host: uri.host,
      port: port,
      useHttps: useHttps,
    );
  }

  Uri _uriForPath(String path) {
    return Uri(
      scheme: useHttps ? 'https' : 'http',
      host: host,
      port: port,
      path: path,
    );
  }

  static _ParsedHostInput _parseHostInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return const _ParsedHostInput(host: '', port: null);
    }

    final candidate =
        trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(candidate);
    if (uri != null && uri.host.isNotEmpty) {
      return _ParsedHostInput(
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
      );
    }

    var sanitized = trimmed;
    if (sanitized.startsWith('http://')) {
      sanitized = sanitized.substring(7);
    } else if (sanitized.startsWith('https://')) {
      sanitized = sanitized.substring(8);
    }
    if (sanitized.contains('/')) {
      sanitized = sanitized.split('/').first;
    }

    if (sanitized.contains(':')) {
      final lastColon = sanitized.lastIndexOf(':');
      final host = sanitized.substring(0, lastColon);
      final parsedPort = int.tryParse(sanitized.substring(lastColon + 1));
      return _ParsedHostInput(host: host, port: parsedPort);
    }

    return _ParsedHostInput(host: sanitized, port: null);
  }
}

class _ParsedHostInput {
  const _ParsedHostInput({
    required this.host,
    required this.port,
  });

  final String host;
  final int? port;
}

class ConnectionValidationResult {
  const ConnectionValidationResult({
    required this.serverDisplayName,
    required this.apiBaseUrl,
    required this.healthStatus,
  });

  final String serverDisplayName;
  final String apiBaseUrl;
  final String healthStatus;
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

class ConnectionConfigurationException extends ApiException {
  ConnectionConfigurationException(super.message);
}

class ConnectionTimeoutException extends ApiException {
  ConnectionTimeoutException(super.message);
}

class HostUnreachableException extends ApiException {
  HostUnreachableException(super.message);
}

class InvalidBackendResponseException extends ApiException {
  InvalidBackendResponseException(super.message);
}

class AuthEndpointUnavailableException extends ApiException {
  AuthEndpointUnavailableException(super.message);
}
