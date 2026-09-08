import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/bluetooth_accessory_manager.dart
// Generates File for Android, Mac, Windows
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'bluetooth_accessory_manager',
    dartOut: 'lib/src/generated/bluetooth_accessory_manager.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/navideck/bluetooth_accessory_manager/BluetoothAccessoryManager.g.kt',
    swiftOut:
        'macos/bluetooth_accessory_manager/Sources/bluetooth_accessory_manager/BluetoothAccessoryManager.g.swift',
    swiftOptions: SwiftOptions(),
    kotlinOptions:
        KotlinOptions(package: 'com.navideck.bluetooth_accessory_manager'),
    cppOptions: CppOptions(namespace: 'bluetooth_accessory_manager'),
    cppHeaderOut: 'windows/BluetoothAccessoryManager.g.h',
    cppSourceOut: 'windows/BluetoothAccessoryManager.g.cpp',
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
