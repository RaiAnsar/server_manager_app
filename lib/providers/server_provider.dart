import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:server_manager_app/models/server.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import shared_preferences
import 'package:uuid/uuid.dart';

class ServerProvider with ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  final _uuid = const Uuid();
  static const _serverListStorageKey = 'serverList'; // Key for SharedPreferences
  static const _serverSecurePrefix = 'server_'; // Prefix for secure storage keys

  List<Server> _servers = [];
  bool _isLoading = false;
  String? _error;

   ServerProvider() {
    loadServers(); // Load servers when the provider is created
  }

  // --- Getters ---
  List<Server> get servers => List.unmodifiable(_servers);
   bool get isLoading => _isLoading;
  String? get error => _error;


  // --- Private Helpers ---

  String _passwordStorageKey(String serverId) => '$_serverSecurePrefix${serverId}_password';

   Future<void> _persistServerList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Convert list of Server objects to list of JSON maps (non-sensitive data only)
      final List<String> serverListJson = _servers.map((server) => jsonEncode(server.toJson())).toList();
      await prefs.setStringList(_serverListStorageKey, serverListJson);
      _error = null; // Clear error on success
    } catch (e) {
      _setError('Failed to save server list: $e');
    }
  }

   void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String? errorMessage) {
    if (_error != errorMessage) {
      _error = errorMessage;
      debugPrint("ServerProvider Error: $errorMessage");
      notifyListeners();
    }
  }

  // --- Public Methods ---

  Future<void> loadServers() async {
    _setLoading(true);
    _setError(null);
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? serverListJson = prefs.getStringList(_serverListStorageKey);

      if (serverListJson != null) {
        _servers = serverListJson
            .map((serverJson) => Server.fromJson(jsonDecode(serverJson) as Map<String, dynamic>))
            .toList();
      } else {
         _servers = []; // Initialize if nothing stored yet
      }
       debugPrint("Loaded ${_servers.length} servers.");
    } catch (e) {
       _setError('Failed to load servers: $e');
        _servers = []; // Ensure list is empty on error
    } finally {
       _setLoading(false);
       // No need to notify if _setLoading does it
    }
  }

  // Updated addServer
  Future<bool> addServer({
    required String name,
    required String host,
    required int port,
    required String user,
    required AuthenticationMethod authMethod,
    required ServerType serverType, // <<< ADDED parameter
    String? password, // Needed if authMethod is password
    String? managedKeyId, // Needed if authMethod is managedKey
  }) async {
    _setLoading(true);
    _setError(null);
    bool success = false;
    final serverId = _uuid.v4();

    try {
       // Basic validation
       if (name.trim().isEmpty || host.trim().isEmpty || user.trim().isEmpty) {
         throw Exception("Name, Host, and User cannot be empty.");
       }
       if (authMethod == AuthenticationMethod.password && (password == null || password.isEmpty)) {
         throw Exception("Password is required for Password Authentication.");
       }
       if (authMethod == AuthenticationMethod.managedKey && (managedKeyId == null || managedKeyId.isEmpty)) {
         throw Exception("A Managed Key must be selected for Key Authentication.");
       }

      // **CRITICAL SECURITY STEP:** Store password securely if provided
      if (authMethod == AuthenticationMethod.password && password != null) {
        await _secureStorage.write(key: _passwordStorageKey(serverId), value: password);
        // Ensure managedKeyId is null for password auth server in the model
        managedKeyId = null;
      } else {
        // Ensure password is null if using managed key, and delete any potentially orphaned password
        password = null;
        await _secureStorage.delete(key: _passwordStorageKey(serverId));
      }

      // Create the server object *without* sensitive data in the list item
      final newServer = Server(
        id: serverId,
        name: name.trim(),
        host: host.trim(),
        port: port,
        user: user.trim(),
        authMethod: authMethod,
        password: null, // Never stored in the list model
        managedKeyId: managedKeyId, // Store the ID if using key auth
        serverType: serverType, // <<< Pass the type
      );

      _servers.add(newServer);
      await _persistServerList(); // Save updated list metadata
      success = true;
      debugPrint("Added server: $name ($serverId) with type $serverType");

    } catch (e) {
      _setError('Failed to add server "$name": $e');
      // Clean up potentially written password if server creation failed overall?
       if (authMethod == AuthenticationMethod.password) {
           await _secureStorage.delete(key: _passwordStorageKey(serverId));
       }
    } finally {
       _setLoading(false);
       notifyListeners();
    }
     return success;
  }

  Future<bool> removeServer(String serverId) async {
     _setLoading(true);
     _setError(null);
     bool success = false;
     Server? serverToRemove;
     
     try {
         serverToRemove = _servers.firstWhere((s) => s.id == serverId);
     } catch (e) {
         _setError('Server with ID $serverId not found for removal.');
         _setLoading(false);
         return false;
     }

    try {
      // Remove credentials first (only password stored by this provider)
      await _secureStorage.delete(key: _passwordStorageKey(serverId));
      // Note: Key credentials deletion is handled by KeyProvider when a key is deleted

      _servers.removeWhere((server) => server.id == serverId);
      await _persistServerList(); // Update the persisted server list
      success = true;
      debugPrint("Removed server: ${serverToRemove.name} ($serverId)");

    } catch (e) {
      _setError('Failed to remove server "${serverToRemove.name}": $e');
    } finally {
      _setLoading(false);
      notifyListeners();
    }
    return success;
  }

  // Updated getCredentials - Only handles password retrieval now
  Future<String?> getPassword(String serverId) async {
     _setError(null);
    try {
       final server = _servers.firstWhere((s) => s.id == serverId);
       if (server.authMethod != AuthenticationMethod.password) {
          debugPrint("Attempted to get password for server $serverId which uses key auth.");
          return null; // Or throw error?
       }
       final password = await _secureStorage.read(key: _passwordStorageKey(serverId));
        if (password == null) {
           throw Exception("Password not found in secure storage for server $serverId.");
        }
       return password;
    } catch (e) {
       _setError('Failed to retrieve password for server ID $serverId: $e');
       // Re-throw or return null? Re-throwing might be better for connection logic.
       throw Exception('Failed to retrieve password: $e');
    }
  }
}