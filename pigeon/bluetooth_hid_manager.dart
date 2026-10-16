import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/bluetooth_hid_manager.dart
// Generates File for Android, Mac
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_bluetooth_classic',
    dartOut: 'lib/src/generated/bluetooth_hid_manager.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/navideck/universal_bluetooth_classic/BluetoothHidManager.g.kt',
    swiftOut:
        'macos/universal_bluetooth_classic/Sources/universal_bluetooth_classic/BluetoothHidManager.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOptions: KotlinOptions(
      package: 'com.navideck.universal_bluetooth_classic',
      includeErrorClass: false,
    ),
    // cppOptions: CppOptions(namespace: 'universal_bluetooth_classic'),
    // cppHeaderOut: 'windows/BluetoothHidManager.g.h',
    // cppSourceOut: 'windows/BluetoothHidManager.g.cpp',
    debugGenerators: true,
  ),
)

/// Flutter -> Native
@HostApi()
abstract class BluetoothHidManagerPlatformChannel {
  void closeSdp();

  @async
  void connect(String deviceId);

  @async
  void disconnect(String deviceId);

  void send(String deviceId, Uint8List data);
}

/// Native -> Flutter
@FlutterApi()
abstract class BluetoothHidManagerCallbackChannel {
  void onConnectionStateChanged(String deviceId, bool connected);

  void onSdpServiceRegistrationUpdate(bool registered);

  ReportReply? onGetReport(String deviceId, ReportType type, int bufferSize);

  void onData(String deviceId, Uint8List data);
}

class ReportReply {
  int? error;
  Uint8List? data;
  ReportReply({this.error, this.data});
}

enum ReportType { input, output, feature }
