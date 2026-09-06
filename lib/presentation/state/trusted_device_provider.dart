import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/services/identity_service.dart';
import 'identity_provider.dart';

final trustedDeviceProvider =
    StateNotifierProvider<TrustedDeviceNotifier, List<String>>((ref) {
  final identityService = ref.watch(identityServiceProvider);
  return TrustedDeviceNotifier(identityService);
});

class TrustedDeviceNotifier extends StateNotifier<List<String>> {
  final IdentityService _identityService;

  TrustedDeviceNotifier(this._identityService) : super(const []) {
    loadTrustedDevices();
  }

  Future<void> loadTrustedDevices() async {
    // IdentityService manages trusted devices via SecureStorage
    state = [];
  }

  Future<void> pinDevice(String fingerprint) async {
    await _identityService.pinTrustedDevice(fingerprint);
    if (!state.contains(fingerprint)) {
      state = [...state, fingerprint];
    }
  }

  Future<void> unpinDevice(String fingerprint) async {
    await _identityService.unpinTrustedDevice(fingerprint);
    state = state.where((fp) => fp != fingerprint).toList();
  }
}
