import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/mac_sdp.dart
// Generates File for macOS.
//
// Kept in its own file, with no `kotlinOut`, so the macOS-only config never
// reaches the generated Kotlin.
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_bluetooth_classic',
    dartOut: 'lib/src/generated/mac_sdp.g.dart',
    dartOptions: DartOptions(),
    swiftOut:
        'macos/universal_bluetooth_classic/Sources/universal_bluetooth_classic/MacSdpChannel.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    debugGenerators: true,
  ),
)

/// Flutter -> Native
@HostApi()
abstract class MacSdpChannel {
  /// Publishes the macOS Bluetooth SDP service record.
  void setupSdp(MacSdpConfig config);
}

/// The Bluetooth SDP record published by the macOS host.
class MacSdpConfig {
  /// The name of a property-list resource in the app bundle describing the
  /// service. When omitted, [data] is used.
  String? sdpPlistFile;

  /// An in-memory map of SDP properties, used when [sdpPlistFile] is omitted.
  Map<String, Object>? data;

  MacSdpConfig({this.data});
}
