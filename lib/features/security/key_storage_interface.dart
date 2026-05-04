import 'dart:async';
import '../../core/crypto/rsa_key_pair.dart';

abstract interface class IKeyStorage {
  /// Checks if there are any saved keys.
  bool hasKeys();

  /// Loads a saved key pair.
  /// Throws [KeyNotFoundException] if there are no keys.
  Future<RsaKeyPair> load();
  Future<void> save(RsaKeyPair keys);

  /// Deletes saved keys
  Future<void> delete();
}

/// Error: Keys not found in storage.
final class KeyNotFoundException implements Exception {
  const KeyNotFoundException([this.message = 'RSA keys not found']);
  final String message;

  @override
  String toString() => message;
}