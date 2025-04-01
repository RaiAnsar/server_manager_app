import 'package:flutter/material.dart';
import 'package:server_manager_app/screens/key_management_screen.dart';
import 'package:server_manager_app/screens/server_list_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // Index for the selected screen

  // List of screens to navigate between
  static const List<Widget> _widgetOptions = <Widget>[
    ServerListScreen(), // Index 0
    KeyManagementScreen(), // Index 1
    // Add Placeholder for Settings later if needed
    // SettingsScreen(), // Index 2
  ];

  // Titles corresponding to the screens
  static const List<String> _widgetTitles = <String>[
    'Managed Servers',
    'Manage SSH Keys',
    // 'Settings',
  ];


  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    Navigator.pop(context); // Close the drawer
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_widgetTitles.elementAt(_selectedIndex)), // Dynamic title
        centerTitle: true,
      ),
      // Drawer for navigation
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero, // Remove default padding
          children: [
            // Optional: Drawer Header
            DrawerHeader(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
              ),
              child: Text(
                'Server Manager',
                style: TextStyle(
                    fontSize: 24,
                    color: Theme.of(context).colorScheme.onPrimaryContainer
                ),
              ),
            ),
            // Navigation Items
            ListTile(
              leading: const Icon(Icons.dns_rounded),
              title: const Text('Servers'),
              selected: _selectedIndex == 0, // Highlight selected item
              onTap: () => _onItemTapped(0),
            ),
            ListTile(
              leading: const Icon(Icons.security_outlined),
              title: const Text('Manage SSH Keys'),
              selected: _selectedIndex == 1,
              onTap: () => _onItemTapped(1),
            ),
            // Divider(),
            // ListTile(
            //   leading: Icon(Icons.settings_outlined),
            //   title: Text('Settings'),
            //   selected: _selectedIndex == 2,
            //   onTap: () => _onItemTapped(2),
            // ),
          ],
        ),
      ),
      // Body displays the currently selected screen from _widgetOptions
      body: IndexedStack( // Use IndexedStack to keep state of inactive screens
         index: _selectedIndex,
         children: _widgetOptions,
      ),
      // Keep FAB only on ServerListScreen? Or move logic inside that screen?
      // For now, the FAB will only appear if the ServerListScreen defines it.
      // floatingActionButton: _selectedIndex == 0
      //      ? FloatingActionButton(...) // FAB specific to ServerListScreen
      //      : null, // No FAB for KeyManagementScreen
    );
  }
}