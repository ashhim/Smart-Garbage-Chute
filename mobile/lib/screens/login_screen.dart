import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController(
    text: 'admin@alghurair.local',
  );
  final TextEditingController _passwordController = TextEditingController(
    text: 'Admin@12345',
  );
  final TextEditingController _apiBaseController = TextEditingController();

  bool _isLoading = false;
  bool _isProbing = false;
  bool _endpointInitialized = false;
  String? _errorMessage;
  String? _probeMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_endpointInitialized) {
      return;
    }

    _apiBaseController.text = context.read<ApiService>().apiBaseUrl;
    _endpointInitialized = true;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _apiBaseController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _probeMessage = null;
    });

    final apiService = context.read<ApiService>();
    final authService = context.read<AuthService>();

    try {
      await apiService.configureBaseUrl(_apiBaseController.text);
      final success = await authService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        if (!success) {
          _errorMessage = authService.lastError ??
              'Login failed. Verify the backend URL and seeded credentials.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'Login failed: $error';
      });
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isProbing = true;
      _errorMessage = null;
      _probeMessage = null;
    });

    final apiService = context.read<ApiService>();
    try {
      await apiService.configureBaseUrl(_apiBaseController.text);
      final response = await apiService.probe();

      if (!mounted) {
        return;
      }

      setState(() {
        _isProbing = false;
        _probeMessage =
            'Backend reachable. API health: ${response['status'] ?? 'ok'}.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isProbing = false;
        _errorMessage = 'Connection test failed: $error';
      });
    }
  }

  void _usePreset(String value) {
    setState(() {
      _apiBaseController.text = value;
      _probeMessage = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final apiService = context.watch<ApiService>();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.delete_outline_rounded,
                    size: 84,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Smart Garbage Chute',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Mobile control-room client for live alerts, rooms, devices, operations, and role-based access.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey.shade700,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          TextField(
                            controller: _apiBaseController,
                            decoration: InputDecoration(
                              labelText: 'Backend API URL',
                              helperText:
                                  'Examples: http://10.0.2.2:8520/api or http://192.168.1.20:8520/api',
                              prefixIcon: const Icon(Icons.link_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => _usePreset(
                                  'http://10.0.2.2:8520/api',
                                ),
                                child: const Text('Android Emulator'),
                              ),
                              OutlinedButton(
                                onPressed: () => _usePreset(
                                  apiService.defaultApiBaseUrl,
                                ),
                                child: const Text('This Machine'),
                              ),
                              TextButton(
                                onPressed: () async {
                                  await apiService.resetBaseUrl();
                                  _usePreset(apiService.apiBaseUrl);
                                },
                                child: const Text('Reset'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: 'Email',
                              prefixIcon: const Icon(Icons.email_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            obscureText: true,
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _errorMessage!,
                                style: TextStyle(color: Colors.red.shade800),
                              ),
                            ),
                          ],
                          if (_probeMessage != null) ...[
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _probeMessage!,
                                style: TextStyle(color: Colors.green.shade800),
                              ),
                            ),
                          ],
                          const SizedBox(height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isLoading || _isProbing
                                      ? null
                                      : _testConnection,
                                  child: _isProbing
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Test Connection'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _isLoading ? null : _handleLogin,
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Sign In'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Current API: ${apiService.apiBaseUrl}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'LAN phones should use your computer IP on port 8520.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
