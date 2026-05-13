import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  bool _useHttps = false;
  bool _isConnecting = false;
  String? _errorMessage;
  String? _statusMessage;

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_hostController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Enter the server IP or host name.';
        _statusMessage = null;
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _statusMessage = 'Validating server connection...';
    });

    final apiService = context.read<ApiService>();

    try {
      final result = await apiService.validateAndConfigureConnection(
        hostInput: _hostController.text,
        portInput: _portController.text,
        useHttps: _useHttps,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isConnecting = false;
        _statusMessage =
            'Connected to ${result.serverDisplayName}. Ready for sign-in.';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isConnecting = false;
        _statusMessage = null;
        _errorMessage = _describeConnectionError(error);
      });
    }
  }

  String _describeConnectionError(Object error) {
    if (error is ConnectionTimeoutException) {
      return 'The server timed out. Check the host, port, and network path.';
    }
    if (error is HostUnreachableException) {
      return 'The server could not be reached. Confirm the host name, IP, and network access.';
    }
    if (error is InvalidBackendResponseException) {
      return 'The server responded, but it does not match the monitoring backend.';
    }
    if (error is AuthEndpointUnavailableException) {
      return 'The server is reachable, but sign-in services are unavailable.';
    }
    if (error is ApiException) {
      return error.message;
    }
    return 'Connection failed. Review the server details and try again.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                children: [
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F5C7A),
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x220F5C7A),
                          blurRadius: 24,
                          offset: Offset(0, 12),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.router_outlined,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Server Connection',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Connect this mobile client to the monitoring server before sign-in.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatusStrip(),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _hostController,
                            decoration: InputDecoration(
                              labelText: 'Server IP or Host',
                              hintText: '192.168.0.190',
                              prefixIcon: const Icon(Icons.dns_outlined),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.url,
                            autocorrect: false,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _portController,
                            decoration: InputDecoration(
                              labelText: 'Port (Optional)',
                              hintText: '8520',
                              prefixIcon: const Icon(Icons.settings_ethernet),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.blueGrey.shade100),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.verified_user_outlined),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text('Use secure HTTPS transport'),
                                ),
                                Switch(
                                  value: _useHttps,
                                  onChanged: _isConnecting
                                      ? null
                                      : (value) =>
                                          setState(() => _useHttps = value),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: const [
                              _ExampleChip('192.168.0.190'),
                              _ExampleChip('monitor.company.local'),
                              _ExampleChip('monitoring.example.com'),
                            ],
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            _FeedbackPanel(
                              background: Colors.red.shade50,
                              foreground: Colors.red.shade800,
                              icon: Icons.error_outline,
                              message: _errorMessage!,
                            ),
                          ],
                          if (_statusMessage != null) ...[
                            const SizedBox(height: 16),
                            _FeedbackPanel(
                              background: Colors.green.shade50,
                              foreground: Colors.green.shade800,
                              icon: Icons.cloud_done_outlined,
                              message: _statusMessage!,
                            ),
                          ],
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: _isConnecting ? null : _connect,
                              child: _isConnecting
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Connect'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusStrip() {
    final hasStatus = _statusMessage != null;
    final hasError = _errorMessage != null;
    final color = hasError
        ? Colors.red
        : hasStatus
            ? Colors.green
            : Colors.orange;
    final label = hasError
        ? 'Connection issue'
        : hasStatus
            ? 'Server verified'
            : 'Awaiting connection';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 12, color: color),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: color.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  const _ExampleChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.blueGrey.shade50,
    );
  }
}

class _FeedbackPanel extends StatelessWidget {
  const _FeedbackPanel({
    required this.background,
    required this.foreground,
    required this.icon,
    required this.message,
  });

  final Color background;
  final Color foreground;
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
