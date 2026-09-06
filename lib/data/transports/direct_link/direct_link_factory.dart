import 'dart:io';

import '../../../domain/contracts/direct_link_adapter.dart';
import 'android_hotspot_adapter.dart';
import 'linux_nm_adapter.dart';
import 'unsupported_direct_adapter.dart';
import 'windows_direct_adapter.dart';

/// Factory providing platform-adaptive DirectLinkAdapter instances
class DirectLinkFactory {
  DirectLinkFactory._();

  /// Create platform-appropriate DirectLinkAdapter
  static DirectLinkAdapter createPlatformAdapter() {
    if (Platform.isAndroid) {
      return AndroidHotspotAdapter();
    } else if (Platform.isLinux) {
      return LinuxNmAdapter();
    } else if (Platform.isWindows) {
      return WindowsDirectAdapter();
    } else {
      return const UnsupportedDirectAdapter(
        reason: 'Direct Link is not supported on this platform.',
      );
    }
  }
}
