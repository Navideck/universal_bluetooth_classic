import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/universal_bluetooth.dart
// Generates File for Android, Mac, Windows
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_bluetooth',
    dartOut: 'lib/src/generated/universal_bluetooth.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/navideck/universal_bluetooth/UniversalBluetooth.g.kt',
    swiftOut:
        'macos/universal_bluetooth/Sources/universal_bluetooth/UniversalBluetooth.g.swift',
    swiftOptions: SwiftOptions(),
    kotlinOptions: KotlinOptions(package: 'com.navideck.universal_bluetooth'),
    cppOptions: CppOptions(namespace: 'universal_bluetooth'),
    cppHeaderOut: 'windows/UniversalBluetooth.g.h',
    cppSourceOut: 'windows/UniversalBluetooth.g.cpp',
    debugGenerators: true,
  ),
)

/// Flutter -> Native
@HostApi()
abstract class FlutterAccessoryPlatformChannel {
  @async
  void showBluetoothAccessoryPicker(List<String> withNames);

  void startScan();

  void stopScan();

  bool isScanning();

  List<BluetoothDevice> getPairedDevices();

  @async
  bool pair(String address);

  @async
  void unpair(String address);
}

/// Native -> Flutter
@FlutterApi()
abstract class FlutterAccessoryCallbackChannel {
  void onDeviceDiscover(BluetoothDevice device);

  void onDeviceRemoved(BluetoothDevice device);
}

class BluetoothDevice {
  String address;
  String? name;
  bool paired;
  bool? isConnectedWithHid;
  int rssi;
  DeviceClass? deviceClass;
  DeviceType? deviceType;

  BluetoothDevice({
    required this.address,
    required this.name,
    required this.paired,
    required this.rssi,
  });
}

enum DeviceClass {
  audioVideo,
  computer,
  health,
  imaging,
  misc,
  networking,
  peripheral,
  phone,
  toy,
  uncategorized,
  wearable,
}

enum DeviceType {
  classic,
  le,
  dual,
  unknown,
}
