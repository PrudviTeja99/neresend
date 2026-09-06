/// Supported network transport modes for DropFlow
enum TransferMode {
  lan,
  direct,
  remote;

  String get displayName {
    switch (this) {
      case TransferMode.lan:
        return 'Local Wi-Fi';
      case TransferMode.direct:
        return 'Direct Offline';
      case TransferMode.remote:
        return 'Remote Internet';
    }
  }
}

/// Target operating system of discovered peers
enum DeviceType {
  android,
  linux,
  windows,
  macos,
  ios,
  web,
  unknown;

  static DeviceType fromString(String? type) {
    if (type == null) return DeviceType.unknown;
    switch (type.toLowerCase()) {
      case 'android':
        return DeviceType.android;
      case 'linux':
        return DeviceType.linux;
      case 'windows':
        return DeviceType.windows;
      case 'macos':
        return DeviceType.macos;
      case 'ios':
        return DeviceType.ios;
      case 'web':
        return DeviceType.web;
      default:
        return DeviceType.unknown;
    }
  }
}

