import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:server_manager_app/models/server.dart';
import 'package:server_manager_app/providers/server_provider.dart';
import 'package:server_manager_app/screens/add_server_screen.dart';
import 'package:server_manager_app/screens/server_detail_screen.dart';


// (Keep the _showDeleteConfirmation method as it was)
void _showDeleteConfirmationDialog(BuildContext context, ServerProvider serverProvider, Server serverToDelete) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm Deletion'),
      content: Text('Are you sure you want to remove server "${serverToDelete.name}"? This cannot be undone.'),
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
            bool success = await serverProvider.removeServer(serverToDelete.id);
            if (success && context.mounted) {
               ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Server "${serverToDelete.name}" removed.'), duration: const Duration(seconds: 2))
               );
            }
            // Error handled by provider
          },
        ),
      ],
    ),
  );
}

class ServerListScreen extends StatelessWidget {
  const ServerListScreen({super.key});
  
  // Add this helper method INSIDE the ServerListScreen class
  IconData _getServerTypeIcon(ServerType type) {
    switch (type) {
      case ServerType.cloudpanel: return Icons.cloud_outlined;
      case ServerType.whmCpanel: return Icons.web_asset_outlined; // Example icon
      case ServerType.generic: return Icons.dns_outlined; // Generic server icon
    }
  }

  @override
  Widget build(BuildContext context) {
    final serverProvider = context.watch<ServerProvider>();
    final servers = serverProvider.servers;
    final isLoading = serverProvider.isLoading;
    final error = serverProvider.error;
    final theme = Theme.of(context); // Get theme for styling

    return Scaffold(
      body: Column(
        children: [
          if (error != null && !isLoading)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text("Error: $error", style: TextStyle(color: theme.colorScheme.error)),
            ),
          // Show linear progress indicator below AppBar when loading list
          if (isLoading)
             const LinearProgressIndicator(), // Changed from Center(CPI)
          Expanded(
            child: servers.isEmpty && !isLoading
                ? Center( // Keep centered for empty state
                    child: Column( // Use column for icon + text
                       mainAxisSize: MainAxisSize.min,
                       children: [
                          Icon(Icons.storage_rounded, size: 60, color: Colors.grey[700]),
                          const SizedBox(height: 16),
                          Text(
                             'No servers added yet.',
                             style: theme.textTheme.headlineSmall?.copyWith(color: Colors.grey),
                           ),
                          const SizedBox(height: 8),
                           Text(
                             'Tap + to add your first server',
                             textAlign: TextAlign.center,
                             style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                           ),
                       ],
                    ),
                  )
                : ListView.builder(
                    // Add padding around the list itself
                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                    itemCount: servers.length,
                    itemBuilder: (context, index) {
                      final server = servers[index];
                      // --- Wrap ListTile in a Card ---
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0), // Add vertical margin between cards
                        elevation: 2, // Subtle shadow
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), // Slightly rounded corners
                        child: ListTile(
                          // Adjust content padding if desired
                          // contentPadding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          leading: CircleAvatar(
                             key: ValueKey('server_avatar_${server.id}'), // Add unique key
                             backgroundColor: theme.colorScheme.secondaryContainer, // Different color?
                             child: Icon( // Main icon based on server type
                                _getServerTypeIcon(server.serverType), // Use helper
                                color: theme.colorScheme.onSecondaryContainer,
                                size: 20,
                             ),
                             // Maybe add a tiny auth badge later?
                          ),
                          title: Text(server.name, style: theme.textTheme.titleMedium),
                          subtitle: Text(
                             '${server.user}@${server.host}:${server.port}',
                              style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[400]), // Smaller, lighter subtitle
                           ),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, color: Colors.redAccent[100]),
                             tooltip: 'Delete Server "${server.name}"',
                            onPressed: () => _showDeleteConfirmationDialog(context, serverProvider, server),
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ServerDetailScreen(server: server),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddServerScreen()),
          );
        },
        tooltip: 'Add Server',
        child: const Icon(Icons.add),
      ),
    );
  }
}