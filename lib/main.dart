import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:server_manager_app/providers/key_provider.dart'; // Import KeyProvider
import 'package:server_manager_app/providers/server_provider.dart';
import 'package:server_manager_app/screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // No need to load providers here anymore, they load themselves in constructors

  runApp(
    // Wrap with MultiProvider
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ServerProvider()),
        ChangeNotifierProvider(create: (_) => KeyProvider()), // Add KeyProvider
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Server Manager',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
        brightness: Brightness.dark,
        // Consider defining colorScheme for better Material 3 theming
        colorScheme: ColorScheme.fromSeed(
             seedColor: Colors.blueGrey,
             brightness: Brightness.dark
        ),
      ),
      home: const MainScreen(), // Use the new main screen with Drawer
      debugShowCheckedModeBanner: false,
    );
  }
}