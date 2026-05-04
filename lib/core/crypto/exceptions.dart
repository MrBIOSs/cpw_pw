/// Base class for cryptographic errors.
sealed class CryptoException implements Exception {
  const CryptoException(this.message, [this.cause]);
  final String message;
  final Object? cause;

  @override
  String toString() => cause != null
      ? '$message: $cause'
      : message;
}

/// Key generation error (not enough entropy, unsupported length).
final class KeyGenerationException extends CryptoException {
  const KeyGenerationException(super.message, [super.cause]);
}

/// Error exporting/importing keys (invalid format, corrupted data).
final class KeyCodecException extends CryptoException {
  const KeyCodecException(super.message, [super.cause]);
}

/// Error saving keys (no write permission, disk is full).
final class KeyStorageException extends CryptoException {
  const KeyStorageException(super.message, [super.cause]);
}