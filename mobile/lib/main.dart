import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: const HomePage(),
    theme: ThemeData.dark(useMaterial3: true),
  );
}

class HomePage extends StatefulWidget { const HomePage({super.key}); @override State<HomePage> createState() => _HomePageState(); }

class _HomePageState extends State<HomePage> {
  late final WebSocketChannel channel;
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
