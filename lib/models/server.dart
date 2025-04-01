import 'package:flutter/foundation.dart';

enum AuthenticationMethod { password, managedKey }

// --- NEW: Server Type Enum ---
enum ServerType {
  generic,      // Default/Unknown
  cloudpanel,
  whmCpanel    // Combined for now, can split later if needed
}

@immutable
class Server {
  final String id; // Unique identifier (e.g., generated UUID)
  final String name; // User-friendly name
  final String host; // IP address or hostname
  final int port;
  final String user;
  final AuthenticationMethod authMethod;
  final String? password; // Store securely! Null if using key
  final String? managedKeyId; // Link to the ID of a ManagedKey
  final ServerType serverType; // <<< NEW FIELD

  const Server({
    required this.id,
    required this.name,
    required this.host,
    this.port = 22, // Default SSH port
    required this.user,
    required this.authMethod,
    this.password, // Only relevant if authMethod is password
    this.managedKeyId, // Only relevant if authMethod is managedKey
    this.serverType = ServerType.generic, // <<< Default value
  });

  // Updated toJson
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'host': host,
        'port': port,
        'user': user,
        'authMethod': authMethod.index, // Store enum index (0 or 1)
        // IMPORTANT: Password is NOT stored here. This is for non-sensitive data persistence.
        'managedKeyId': managedKeyId, // Store the ID if using managedKey
        'serverType': serverType.index, // <<< Add serverType index
      };

  // Updated fromJson
  factory Server.fromJson(Map<String, dynamic> json) {
    // Handle potential loading of old data structure if necessary,
    // for now, assume new structure (index 0=password, 1=managedKey)
    int authMethodIndex = json['authMethod'] as int? ?? 0;
    // Ensure index is valid for the *new* enum length
    if (authMethodIndex >= AuthenticationMethod.values.length) {
      authMethodIndex = 0; // Default to password if index is out of bounds
    }

    // <<< Load serverType index, default to generic (0) if missing/invalid >>>
    int serverTypeIndex = json['serverType'] as int? ?? 0;
    if (serverTypeIndex >= ServerType.values.length) { serverTypeIndex = 0; }

    return Server(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 22,
      user: json['user'] as String,
      authMethod: AuthenticationMethod.values[authMethodIndex],
      managedKeyId: json['managedKeyId'] as String?, // Load the key ID
      // IMPORTANT: Password loading needs secure retrieval logic elsewhere
      password: null, // Load securely on demand using ServerProvider
      serverType: ServerType.values[serverTypeIndex], // <<< Assign loaded type
    );
  }

   // Optional: Override == and hashCode
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Server &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}