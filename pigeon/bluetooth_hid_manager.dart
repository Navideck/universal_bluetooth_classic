import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/bluetooth_hid_manager.dart
// Generates File for Android, Mac
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_bluetooth',
    dartOut: 'lib/src/generated/bluetooth_hid_manager.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/navideck/universal_bluetooth/BluetoothHidManager.g.kt',
    swiftOut:
        'macos/universal_bluetooth/Sources/universal_bluetooth/BluetoothHidManager.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOptions: KotlinOptions(
      package: 'com.navideck.universal_bluetooth',
      includeErrorClass: false,
    ),
    // cppOptions: CppOptions(namespace: 'universal_bluetooth'),
    // cppHeaderOut: 'windows/BluetoothHidManager.g.h',
    // cppSourceOut: 'windows/BluetoothHidManager.g.cpp',
    debugGenerators: true,
  ),
)

/// Flutter -> Native
@HostApi()
abstract class BluetoothHidManagerPlatformChannel {
  void setupSdp(SdpConfig config);

  void closeSdp();

  @async
  void connect(String deviceId);

  @async
  void disconnect(String deviceId);

  void sendReport(String deviceId, Uint8List data);
}

/// Native -> Flutter
@FlutterApi()
abstract class BluetoothHidManagerCallbackChannel {
  void onConnectionStateChanged(String deviceId, bool connected);

  void onSdpServiceRegistrationUpdate(bool registered);

  ReportReply? onGetReport(String deviceId, ReportType type, int bufferSize);
}

class ReportReply {
  int? error;
  Uint8List? data;
  ReportReply({this.error, this.data});
}

enum ReportType { input, output, feature }

class SdpConfig {
  MacSdpConfig? macSdpConfig;
  AndroidSdpConfig? androidSdpConfig;

  SdpConfig({
    required this.macSdpConfig,
    required this.androidSdpConfig,
  });
}

class MacSdpConfig {
  String? sdpPlistFile;
  Map<String, Object>? data;

  MacSdpConfig({this.data});
}

class AndroidSdpConfig {
  String name;
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
