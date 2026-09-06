/// Base exception class for DropFlow errors
abstract class NeReSendException implements Exception {
  final String message;
  final String? code;
  final dynamic cause;

  const NeReSendException(this.message, {this.code, this.cause});

  @override
  String toString() => '$runtimeType: $message${code != null ? ' (code: $code)' : ''}';
}

/// Thrown when binary framing, headers, or frame size invariants are violated
class ProtocolException extends NeReSendException {
  const ProtocolException(super.message, {super.code, super.cause});
}

/// Thrown during cryptographic key generation, signature mismatch, or cert errors
class CryptoException extends NeReSendException {
  const CryptoException(super.message, {super.code, super.cause});
}

/// Thrown when disk space is exhausted, file cannot be written, or path traversal detected
class StorageException extends NeReSendException {
  const StorageException(super.message, {super.code, super.cause});
}

/// Thrown on network socket drop, timeout, or WebRTC transport failures
class NetworkException extends NeReSendException {
  const NetworkException(super.message, {super.code, super.cause});
}

/// Thrown when Direct Link (Wi-Fi Direct / SoftAP) is unavailable on current OS/hardware
class DirectLinkUnavailableException extends NeReSendException {
  const DirectLinkUnavailableException(super.message, {super.code, super.cause});
}

