import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../domain/contracts/secure_storage_port.dart';

/// Concrete implementation of SecureStoragePort using flutter_secure_storage
class SecureStorageAdapter implements SecureStoragePort {
  final FlutterSecureStorage _storage;

  SecureStorageAdapter({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              lOptions: LinuxOptions(),
              wOptions: WindowsOptions(),
            );

  @override
  Future<String?> read(String key) async {
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  @override
  Future<Map<String, String>> readAll() async {
    return _storage.readAll();
  }
}

