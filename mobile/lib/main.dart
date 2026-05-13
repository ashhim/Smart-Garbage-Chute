import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize notification service
  await NotificationService().initialize();
  
  runApp(
    MultiProvider(
      providers: [
        Provider<ApiService>(create: (_) => ApiService()),
        ChangeNotifierProvider<AuthService>(
          create: (context) => AuthService(
            apiService: context.read<ApiService>(),
          ),
        ),
      ],
      child: const SmartGarbageApp(),
    ),
  );
}

class SmartGarbageApp extends StatelessWidget {
  const SmartGarbageApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Garbage Chute',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0066CC),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: Consumer<AuthService>(
        builder: (context, authService, _) {
          if (authService.isAuthenticated) {
            return const DashboardScreen();
          } else {
            return const LoginScreen();
          }
        },
      ),
    );
  }
}
  final List<String> events = [];

  @override
  void initState() {
    super.initState();
    channel = WebSocketChannel.connect(Uri.parse('ws://localhost/ws'));
    channel.stream.listen((event) { setState(() => events.insert(0, event.toString())); });
  }

  @override
  void dispose() { channel.sink.close(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Garbage Chute Mobile')),
    body: ListView.builder(
      itemCount: events.length,
      itemBuilder: (_, i) {
        final e = events[i];
        return ListTile(title: Text('Realtime event'), subtitle: Text(e));
      },
    ),
  );
}
