import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/bluetooth_serial_manager.dart
// Generates File for Android, Mac, Windows
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_bluetooth_classic',
    dartOut: 'lib/src/generated/bluetooth_serial_manager.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/navideck/universal_bluetooth_classic/BluetoothSerialManager.g.kt',
    swiftOut:
        'macos/universal_bluetooth_classic/Sources/universal_bluetooth_classic/BluetoothSerialManager.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOptions: KotlinOptions(
      package: 'com.navideck.universal_bluetooth_classic',
      includeErrorClass: false,
    ),
    cppOptions: CppOptions(namespace: 'universal_bluetooth_classic_serial'),
    cppHeaderOut: 'windows/BluetoothSerialManager.g.h',
    cppSourceOut: 'windows/BluetoothSerialManager.g.cpp',
    debugGenerators: true,
  ),
)

/// Flutter -> Native
@HostApi()
abstract class BluetoothSerialPlatformChannel {
  /// Opens an RFCOMM/SPP connection to [deviceId] for the service [serviceUuid].
  @asyncCallback
  void connect(String deviceId, String serviceUuid);

  /// Closes the RFCOMM/SPP connection to [deviceId].
  @asyncCallback
  void disconnect(String deviceId);

  /// Writes [data] to the RFCOMM/SPP connection to [deviceId].
  ///
  /// Asynchronous so the host can perform the (potentially blocking) socket
  /// write off the platform thread.
  @asyncCallback
  void send(String deviceId, Uint8List data);
}

/// Native -> Flutter
@FlutterApi()
abstract class BluetoothSerialCallbackChannel {
  @asyncCallback
  void onConnectionStateChanged(String deviceId, bool connected);

  @asyncCallback
  void onData(String deviceId, Uint8List data);
}
