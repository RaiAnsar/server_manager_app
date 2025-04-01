// lib/providers/key_provider.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:server_manager_app/models/managed_key.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class KeyProvider with ChangeNotifier {
  final _secureStorage = const FlutterSecureStorage();
  final _uuid = const Uuid();
  static const _keyListStorageKey = 'managedKeyList'; // Key for SharedPreferences
  static const _keySecurePrefix = 'managed_key_'; // Prefix for secure storage keys

  List<ManagedKey> _keys = [];
  bool _isLoading = false;
  String? _error;

  KeyProvider() {
    loadKeys(); // Load keys when the provider is created
  }

  // --- Getters ---
  List<ManagedKey> get keys => List.unmodifiable(_keys);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // --- Private Helper Methods ---

  String _securePrivateKeyStorageKey(String keyId) => '$_keySecurePrefix${keyId}_privateKey';
  String _securePassphraseStorageKey(String keyId) => '$_keySecurePrefix${keyId}_passphrase';

  Future<void> _persistKeyList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Convert list of ManagedKey objects to list of JSON maps
      final List<String> keyListJson = _keys.map((key) => jsonEncode(key.toJson())).toList();
      await prefs.setStringList(_keyListStorageKey, keyListJson);
       _error = null; // Clear error on success
    } catch (e) {
      _setError('Failed to save key list: $e');
      // Decide if you want to re-throw or just notify listeners
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
      debugPrint("KeyProvider Error: $errorMessage"); // Log error
      notifyListeners();
    }
  }


  // --- Public Methods ---

  Future<void> loadKeys() async {
    _setLoading(true);
     _setError(null);
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? keyListJson = prefs.getStringList(_keyListStorageKey);

      if (keyListJson != null) {
        _keys = keyListJson
            .map((keyJson) => ManagedKey.fromJson(jsonDecode(keyJson) as Map<String, dynamic>))
            .toList();
      } else {
        _keys = []; // Initialize empty list if nothing is stored yet
      }
       debugPrint("Loaded ${_keys.length} managed keys.");
    } catch (e) {
       _setError('Failed to load keys: $e');
       _keys = []; // Ensure list is empty on error
    } finally {
       _setLoading(false);
       // No need to call notifyListeners here if _setLoading does it
    }
  }

  Future<bool> addKey({
    required String label,
    required String privateKeyData,
    String? passphrase, // Optional passphrase
  }) async {
     _setLoading(true);
     _setError(null);
     bool success = false;
    try {
      if (label.trim().isEmpty || privateKeyData.trim().isEmpty) {
        throw Exception("Label and Private Key cannot be empty.");
      }

      // Check if label already exists (optional, but good UX)
      if (_keys.any((key) => key.label == label.trim())) {
         throw Exception('A key with the label "$label" already exists.');
      }

      final keyId = _uuid.v4();
      final bool hasPassphrase = passphrase != null && passphrase.isNotEmpty;

      // Store sensitive data securely FIRST
      await _secureStorage.write(key: _securePrivateKeyStorageKey(keyId), value: privateKeyData);
      if (hasPassphrase) {
        await _secureStorage.write(key: _securePassphraseStorageKey(keyId), value: passphrase);
      } else {
         // Ensure old passphrase is removed if key is updated without one
         await _secureStorage.delete(key: _securePassphraseStorageKey(keyId));
      }

      // Add to the list in memory
      final newKey = ManagedKey(id: keyId, label: label.trim(), hasPassphrase: hasPassphrase);
      _keys.add(newKey);

      // Persist the updated list metadata
      await _persistKeyList();
      success = true;
      debugPrint("Added managed key: $label ($keyId)");

    } catch (e) {
       _setError('Failed to add key "$label": $e');
       // No need to manually revert secure storage writes on failure generally,
       // but ensure the key isn't added to the in-memory list or persisted list if storage fails.
    } finally {
       _setLoading(false);
       notifyListeners(); // Notify about loading state change and potential list update/error
    }
    return success;
  }

  Future<bool> removeKey(String keyId) async {
    _setLoading(true);
    _setError(null);
    bool success = false;
    
    // Find the index of the key to remove
    int keyIndex = _keys.indexWhere((key) => key.id == keyId);
    
    // Check if key exists
    if (keyIndex == -1) {
         _setError('Key with ID $keyId not found for removal.');
         _setLoading(false);
         return false;
    }
    
    // Get the key before removing it
    ManagedKey keyToRemove = _keys[keyIndex];

    try {
      // Remove sensitive data FIRST
      await _secureStorage.delete(key: _securePrivateKeyStorageKey(keyId));
      await _secureStorage.delete(key: _securePassphraseStorageKey(keyId)); // Delete passphrase too

      // Remove from the list in memory using the index
      _keys.removeAt(keyIndex);

      // Persist the updated list metadata
      await _persistKeyList();
      success = true;
      debugPrint("Removed managed key: ${keyToRemove.label} ($keyId)");

    } catch (e) {
       _setError('Failed to remove key "${keyToRemove.label}": $e');
       // If secure storage deletion fails, should we put the key back in the list?
       // Arguably no, better to have orphaned secure data than inconsistent state.
       // The key is already removed from _keys at this point. Need to decide if _persistKeyList should happen.
       // For simplicity, we proceed, but log the error.
    } finally {
       _setLoading(false);
       notifyListeners();
    }
    return success;
  }

  // Method to securely get credentials when needed for connection
  Future<Map<String, String?>> getKeyCredentials(String keyId) async {
    // Intentionally don't set loading state here, as this is for background use
    _setError(null);
    try {
      final privateKey = await _secureStorage.read(key: _securePrivateKeyStorageKey(keyId));
      if (privateKey == null) {
        throw Exception("Private key not found in secure storage for ID $keyId");
      }
      // Read passphrase only if the key metadata indicates it exists
      String? passphrase;
      
      // Find the index of the key
      int keyIndex = _keys.indexWhere((k) => k.id == keyId);
      
      // Check if key exists
      if (keyIndex == -1) {
        throw Exception("Private key not found in metadata for ID $keyId");
      }
      
      // Get the key using the index
      final keyMeta = _keys[keyIndex];
      
      if (keyMeta.hasPassphrase) {
         passphrase = await _secureStorage.read(key: _securePassphraseStorageKey(keyId));
         // Decide how to handle missing passphrase if hasPassphrase was true
         // if (passphrase == null) debugPrint("Warning: Key $keyId marked as having passphrase, but none found in secure storage.");
      }

      return {'privateKey': privateKey, 'passphrase': passphrase};
    } catch (e) {
       _setError('Failed to retrieve credentials for key ID $keyId: $e');
      // Re-throw or return empty map? Re-throwing might be better for connection logic.
      throw Exception('Failed to retrieve key credentials: $e');
    }
  }
}