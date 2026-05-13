import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class ApiService {
  static const String baseUrl = 'http://localhost:8000';
  static const String wsUrl = 'ws://localhost:8000/ws';

  String? _token;

  void setToken(String token) {
    _token = token;
  }

  Future<dynamic> get(String endpoint) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: _getHeaders(),
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw UnauthorizedException('Unauthorized');
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<dynamic> post(String endpoint, Map<String, dynamic> body) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl$endpoint'),
        headers: _getHeaders(),
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else if (response.statusCode == 401) {
        throw UnauthorizedException('Unauthorized');
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  WebSocketChannel connectWebSocket() {
    return WebSocketChannel.connect(Uri.parse('$wsUrl?token=$_token'));
  }

  Map<String, String> _getHeaders() {
    final headers = {'Content-Type': 'application/json'};

    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }

    return headers;
  }
}

class UnauthorizedException implements Exception {
  final String message;
  UnauthorizedException(this.message);

  @override
  String toString() => message;
}
