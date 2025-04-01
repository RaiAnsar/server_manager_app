// lib/screens/key_management_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:server_manager_app/models/managed_key.dart';
import 'package:server_manager_app/providers/key_provider.dart';
// Import AddKeyScreen later when created
import 'package:server_manager_app/screens/add_key_screen.dart';

class KeyManagementScreen extends StatelessWidget {
  const KeyManagementScreen({super.key});

  void _showDeleteConfirmation(BuildContext context, KeyProvider keyProvider, ManagedKey keyToDelete) {
     showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text('Are you sure you want to delete the key "${keyToDelete.label}"? This cannot be undone and servers using this key will fail to connect.'),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('Delete'),
            onPressed: () async {
               Navigator.of(ctx).pop(); // Close dialog first
               bool success = await keyProvider.removeKey(keyToDelete.id);
               if (success && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text('Key "${keyToDelete.label}" deleted.'), duration: const Duration(seconds: 2))
                  );
               }
               // Error display handled by provider snackbar/state
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Use watch to rebuild when keys change
    final keyProvider = context.watch<KeyProvider>();
    final keys = keyProvider.keys;
    final isLoading = keyProvider.isLoading;
    final error = keyProvider.error; // Get error state

    return Scaffold(
      body: Column( // Use Column to show loading/error messages easily
        children: [
          // Display error message if any
          if (error != null && !isLoading)
             Padding(
               padding: const EdgeInsets.all(8.0),
               child: Text("Error: $error", style: TextStyle(color: Theme.of(context).colorScheme.error)),
             ),
           // Display loading indicator
          if (isLoading)
             const Padding(
               padding: EdgeInsets.all(8.0),
               child: Center(child: CircularProgressIndicator()),
             ),
          // Display key list or empty message
          Expanded( // Make ListView take remaining space
             child: keys.isEmpty && !isLoading
              ? const Center(
                  child: Text(
                    'No SSH keys added yet.\nTap + to add one!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  itemCount: keys.length,
                  itemBuilder: (context, index) {
                    final key = keys[index];
                    return ListTile(
                      leading: Icon(Icons.vpn_key_outlined, color: Theme.of(context).colorScheme.primary),
                      title: Text(key.label),
                       subtitle: key.hasPassphrase ? const Text("Requires passphrase") : null,
                      trailing: isLoading // Disable delete button while loading
                          ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                          : IconButton(
                              icon: Icon(Icons.delete_outline, color: Colors.redAccent[100]),
                              tooltip: 'Delete Key "${key.label}"',
                              onPressed: () => _showDeleteConfirmation(context, keyProvider, key),
                            ),
                      onTap: () {
                        // Optional: Navigate to a key detail/edit screen in the future
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Tapped on ${key.label}. Edit not implemented.'), duration: const Duration(seconds: 1))
                        );
                      },
                    );
                  },
                ),
          ),

        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Navigate to the screen for adding a new key
           Navigator.push(
             context,
             MaterialPageRoute(builder: (context) => const AddKeyScreen()), // Create this screen next
           );
        },
        tooltip: 'Add SSH Key',
        child: const Icon(Icons.add),
      ),
    );
  }
}