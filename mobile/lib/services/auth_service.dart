import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/user.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  AuthService({required this.apiService});

  static const _tokenKey = 'auth_token';
  static const _emailKey = 'auth_email';

  final ApiService apiService;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _token;
  String? _email;
  AppUser? _currentUser;
  String? _lastError;
  bool _isAuthenticated = false;
  bool _isReady = false;

  String? get token => _token;
  String? get email => _email;
  AppUser? get currentUser => _currentUser;
  String? get lastError => _lastError;
  bool get isAuthenticated => _isAuthenticated;
  bool get isReady => _isReady;
  bool get canUseSimulation => _currentUser?.canUseSimulation ?? false;
  bool get canAcknowledgeAlerts => _currentUser?.canAcknowledgeAlerts ?? false;

  Future<void> initialize() async {
    _token = await _storage.read(key: _tokenKey);
    _email = await _storage.read(key: _emailKey);
    apiService.setToken(_token);

    if (_token != null && _token!.isNotEmpty) {
      try {
        await _loadCurrentUser();
        _isAuthenticated = true;
      } catch (error) {
        debugPrint('Auth restore error: $error');
        await _clearSession(notify: false);
      }
    }

    _isReady = true;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _lastError = null;

    try {
      final result = await apiService.post('/auth/login', {
        'email': email,
        'password': password,
      });
      final payload = apiService.expectMap(result);

      if (payload['access_token'] == null) {
        _lastError = 'Missing access token in login response.';
        return false;
      }

      _token = payload['access_token'].toString();
      _email = email;
      apiService.setToken(_token);

      await _loadCurrentUser();

      _isAuthenticated = true;
      await _storage.write(key: _tokenKey, value: _token);
      await _storage.write(key: _emailKey, value: email);

      notifyListeners();
      return true;
    } catch (error) {
      _lastError = _describeError(error);
      debugPrint('Login error: $error');
      await _clearSession(notify: false);
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _clearSession();
  }

  Future<void> _loadCurrentUser() async {
    final result = await apiService.get('/auth/me');
    _currentUser = AppUser.fromJson(apiService.expectMap(result));
  }

  Future<void> _clearSession({bool notify = true}) async {
    _token = null;
    _email = null;
    _currentUser = null;
    _isAuthenticated = false;
    apiService.setToken(null);

    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _emailKey);

    if (notify) {
      notifyListeners();
    }
  }

  String _describeError(Object error) {
    if (error is ApiException) {
      return error.message;
    }
    return error.toString();
  }
}
