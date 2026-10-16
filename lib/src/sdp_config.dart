import 'package:universal_bluetooth_classic/src/generated/android_sdp.g.dart';
import 'package:universal_bluetooth_classic/src/generated/mac_sdp.g.dart';

/// Platform-specific configuration for [UniversalBluetooth.setupSdp].
///
/// Only the entry for the current platform is used, so a cross-platform app can
/// build a single [SdpConfig] and hand it to [UniversalBluetooth.setupSdp]
/// without knowing which platform it is running on.
///
/// This type deliberately lives in Dart rather than in the Pigeon definitions:
/// the native channels take only their own platform's config
/// ([AndroidSdpConfig] or [MacSdpConfig]), so neither platform's generated code
/// has to carry the other platform's type.
class SdpConfig {
  SdpConfig({
    this.macSdpConfig,
    this.androidSdpConfig,
  });

  /// The macOS SDP record, used when registering on macOS.
  MacSdpConfig? macSdpConfig;

  /// The Android SDP record, used when registering on Android.
  AndroidSdpConfig? androidSdpConfig;

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  bool operator ==(Object other) {
    if (other is! SdpConfig || other.runtimeType != runtimeType) {
      return false;
    }
    if (identical(this, other)) {
      return true;
    }
    return macSdpConfig == other.macSdpConfig &&
        androidSdpConfig == other.androidSdpConfig;
  }

  @override
  // ignore: avoid_equals_and_hash_code_on_mutable_classes
  int get hashCode => Object.hash(runtimeType, macSdpConfig, androidSdpConfig);

  @override
  String toString() {
    return 'SdpConfig(macSdpConfig: $macSdpConfig, '
        'androidSdpConfig: $androidSdpConfig)';
  }
}
