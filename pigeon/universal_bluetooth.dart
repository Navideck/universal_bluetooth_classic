import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/universal_bluetooth.dart
// Generates File for Android, Mac, Windows
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_bluetooth_classic',
    dartOut: 'lib/src/generated/universal_bluetooth.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/navideck/universal_bluetooth_classic/UniversalBluetooth.g.kt',
    swiftOut:
        'macos/universal_bluetooth_classic/Sources/universal_bluetooth_classic/UniversalBluetooth.g.swift',
    swiftOptions: SwiftOptions(),
    kotlinOptions:
        KotlinOptions(package: 'com.navideck.universal_bluetooth_classic'),
    cppOptions: CppOptions(namespace: 'universal_bluetooth_classic'),
    cppHeaderOut: 'windows/UniversalBluetooth.g.h',
    cppSourceOut: 'windows/UniversalBluetooth.g.cpp',
    debugGenerators: true,
  ),
)

/// Flutter -> Native
@HostApi()
abstract class FlutterAccessoryPlatformChannel {
  @asyncCallback
  void showBluetoothAccessoryPicker(List<String> withNames);

  void startScan();

  void stopScan();

  bool isScanning();

  List<BluetoothDevice> getPairedDevices();

  @asyncCallback
  bool pair(String address);

  @asyncCallback
  void unpair(String address);
}

/// Native -> Flutter
@FlutterApi()
abstract class FlutterAccessoryCallbackChannel {
  @asyncCallback
  void onDeviceDiscover(BluetoothDevice device);

  @asyncCallback
  void onDeviceRemoved(BluetoothDevice device);
}

/// A discovered or paired Bluetooth device.
class BluetoothDevice {
  /// The device address, or the connection ID on iOS.
  String address;

  /// The human-readable device name, when known.
  String? name;

  /// Whether the device is paired.
  bool paired;

  /// Whether the device is connected over HID.
  bool? isConnectedWithHid;

  /// The received signal strength indicator, in dBm.
  int rssi;

  /// The device class.
  DeviceClass? deviceClass;

  /// The device type.
  DeviceType? deviceType;

  BluetoothDevice({
    required this.address,
    required this.name,
    required this.paired,
    required this.rssi,
  });
}

/// The class of a Bluetooth device.
enum DeviceClass {
  /// Audio or video device, for example a headset or speaker.
  audioVideo,

  /// Computer or computer-like device.
  computer,

  /// Health device, for example a heart-rate monitor.
  health,

  /// Imaging device, for example a printer.
  imaging,

  /// Miscellaneous device.
  misc,

  /// Networking device, for example a modem or router.
  networking,

  /// Peripheral device, for example a keyboard or mouse.
  peripheral,

  /// Phone or smartphone.
  phone,

  /// Toy.
  toy,

  /// Uncategorized device.
  uncategorized,

  /// Wearable device.
  wearable,
}

/// The type of a Bluetooth device.
enum DeviceType {
  /// Bluetooth Classic device.
  classic,

  /// Bluetooth Low Energy device.
  le,

  /// Dual-mode device supporting both Classic and LE.
  dual,

  /// Unknown type.
  unknown,
}
