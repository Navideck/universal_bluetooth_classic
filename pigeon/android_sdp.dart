import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/android_sdp.dart
// Generates File for Android.
//
// Kept in its own file, with no `swiftOut`, so the Android-only config never
// reaches the generated Swift (which rejects a field named `description`).
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_bluetooth_classic',
    dartOut: 'lib/src/generated/android_sdp.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/navideck/universal_bluetooth_classic/AndroidSdpChannel.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.navideck.universal_bluetooth_classic',
      includeErrorClass: false,
    ),
    debugGenerators: true,
  ),
)

/// Flutter -> Native
@HostApi()
abstract class AndroidSdpChannel {
  /// Registers the Android Bluetooth HID Device application with this SDP
  /// record.
  void setupSdp(AndroidSdpConfig config);
}

/// The Bluetooth SDP record used to register the Android HID device app.
class AndroidSdpConfig {
  String name;

  /// The service description advertised in the SDP record.
  String description;

  String provider;
  int subclass;
  Uint8List descriptors;

  AndroidSdpConfig({
    required this.name,
    required this.description,
    required this.provider,
    required this.subclass,
    required this.descriptors,
  });
}
