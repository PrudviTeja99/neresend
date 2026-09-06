import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/identity_service.dart';
import '../../data/services/secure_storage_adapter.dart';
import '../../domain/models/device_identity.dart';

final secureStorageProvider = Provider<SecureStorageAdapter>((ref) {
  return SecureStorageAdapter();
});

final identityServiceProvider = Provider<IdentityService>((ref) {
  final storage = ref.watch(secureStorageProvider);
  return IdentityService(secureStorage: storage);
});

final identityStateProvider = StateNotifierProvider<IdentityNotifier, AsyncValue<DeviceIdentity>>((ref) {
  final service = ref.watch(identityServiceProvider);
  return IdentityNotifier(service);
});

class IdentityNotifier extends StateNotifier<AsyncValue<DeviceIdentity>> {
  final IdentityService _service;

  IdentityNotifier(this._service) : super(const AsyncValue.loading()) {
    loadIdentity();
  }

  Future<void> loadIdentity() async {
    try {
      state = const AsyncValue.loading();
      final identity = await _service.initialize();
      state = AsyncValue.data(identity);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> updateAlias(String newAlias) async {
    try {
      await _service.updateAlias(newAlias);
      if (_service.currentIdentity != null) {
        state = AsyncValue.data(_service.currentIdentity!);
      }
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

