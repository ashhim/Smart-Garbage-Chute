import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  final ApiService apiService;
  final _storage = const FlutterSecureStorage();

  String? _token;
  String? _email;
  bool _isAuthenticated = false;

  AuthService({required this.apiService}) {
    _loadToken();
  }

  String? get token => _token;
  String? get email => _email;
  bool get isAuthenticated => _isAuthenticated;

  Future<void> _loadToken() async {
    _token = await _storage.read(key: 'auth_token');
    _email = await _storage.read(key: 'auth_email');
    _isAuthenticated = _token != null;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final result = await apiService.post('/auth/login', {
        'email': email,
        'password': password,
      });

      if (result['access_token'] != null) {
        _token = result['access_token'];
        _email = email;
        _isAuthenticated = true;

        await _storage.write(key: 'auth_token', value: _token!);
        await _storage.write(key: 'auth_email', value: email);

        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Login error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    _token = null;
    _email = null;
    _isAuthenticated = false;

    await _storage.delete(key: 'auth_token');
    await _storage.delete(key: 'auth_email');

    notifyListeners();
  }
}
