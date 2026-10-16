/// A Flutter plugin for discovering, pairing, and managing Bluetooth Classic
/// accessories, Bluetooth HID devices, and Apple External Accessory sessions.
///
/// Use the [UniversalBluetooth] class as the single entry point for all
/// platforms.
library;

export 'package:universal_bluetooth_classic/src/generated/external_accessory.g.dart'
    show EAAccessory;
export 'package:universal_bluetooth_classic/src/generated/universal_bluetooth.g.dart'
    show BluetoothDevice, DeviceType, DeviceClass;
export 'package:universal_bluetooth_classic/src/generated/android_sdp.g.dart'
    show AndroidSdpConfig;
export 'package:universal_bluetooth_classic/src/generated/bluetooth_hid_manager.g.dart'
    show ReportReply, ReportType;
export 'package:universal_bluetooth_classic/src/generated/mac_sdp.g.dart'
    show MacSdpConfig;
export 'package:universal_bluetooth_classic/src/sdp_config.dart';
export 'package:universal_bluetooth_classic/src/universal_bluetooth.dart';
export 'package:universal_bluetooth_classic/src/universal_bluetooth_interface.dart';
