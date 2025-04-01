// lib/models/managed_key.dart
import 'package:flutter/foundation.dart';

@immutable // Good practice for models used in providers
class ManagedKey {
  final String id; // Unique identifier (e.g., generated UUID)
  final String label; // User-friendly name (e.g., "Work Laptop Key")
  final bool hasPassphrase; // Indicates if a passphrase is stored securely

  const ManagedKey({
    required this.id,
    required this.label,
    required this.hasPassphrase,
  });

  // --- Serialization for non-sensitive data (e.g., storing list in SharedPreferences) ---

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'hasPassphrase': hasPassphrase,
      };

  factory ManagedKey.fromJson(Map<String, dynamic> json) {
    return ManagedKey(
      id: json['id'] as String,
      label: json['label'] as String,
      hasPassphrase: json['hasPassphrase'] as bool? ?? false, // Default to false if missing
    );
  }

  // Optional: Override == and hashCode for comparisons if needed
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ManagedKey &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}