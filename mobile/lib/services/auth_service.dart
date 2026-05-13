import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_service.dart';

class AuthService extends ChangeNotifier {
  AuthService({required this.apiService});

  static const _tokenKey = 'auth_token';
  static const _emailKey = 'auth_email';

  final ApiService apiService;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _token;
  String? _email;
  bool _isAuthenticated = false;
  bool _isReady = false;

  String? get token => _token;
  String? get email => _email;
  bool get isAuthenticated => _isAuthenticated;
  bool get isReady => _isReady;

  Future<void> initialize() async {
    _token = await _storage.read(key: _tokenKey);
    _email = await _storage.read(key: _emailKey);
    _isAuthenticated = _token != null && _token!.isNotEmpty;
    apiService.setToken(_token);
    _isReady = true;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final result = await apiService.post('/auth/login', {
        'email': email,
        'password': password,
      });
      final payload = apiService.expectMap(result);

      if (payload['access_token'] == null) {
        return false;
      }

      _token = payload['access_token'].toString();
      _email = email;
      _isAuthenticated = true;
      apiService.setToken(_token);

      await _storage.write(key: _tokenKey, value: _token);
      await _storage.write(key: _emailKey, value: email);

      notifyListeners();
      return true;
    } catch (error) {
      debugPrint('Login error: $error');
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _email = null;
    _isAuthenticated = false;
    apiService.setToken(null);

    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _emailKey);

    notifyListeners();
  }
}
