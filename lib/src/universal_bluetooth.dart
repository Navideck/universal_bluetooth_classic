import 'package:flutter/foundation.dart';
import 'package:universal_bluetooth_classic/universal_bluetooth_classic.dart';
import 'package:universal_bluetooth_classic/src/platforms/accessory_manager.dart';
import 'package:universal_bluetooth_classic/src/platforms/accessory_manager_bluez.dart';
import 'package:universal_bluetooth_classic/src/platforms/external_accessory.dart';

class UniversalBluetooth {
  /// Default platform accessor.
  static UniversalBluetoothInterface? _platformInstance;
  static UniversalBluetoothInterface get _platform =>
      _platformInstance ??= _defaultPlatform();

  /// Set custom platform specific implementation (e.g. for testing).
  static void setInstance(UniversalBluetoothInterface? instance) {
    _platformInstance = instance;
  }

  static Future<void> showBluetoothAccessoryPicker({
    List<String> withNames = const [],
  }) {
    return _platform.showBluetoothAccessoryPicker(withNames: withNames);
  }

  /// Disconnects a Bluetooth device or closes an iOS External Accessory
  /// session.
  ///
  /// [identifier] is the device ID on Android, macOS, Windows, and Linux. On
  /// iOS it is an optional protocol string; when omitted, the first available
  /// protocol is used.
  static Future<void> disconnect([String? identifier]) =>
      _platform.disconnect(identifier);

  static Future<void> connect(String deviceId) => _platform.connect(deviceId);

  static Future<void> sendReport(String deviceId, Uint8List data) =>
      _platform.sendReport(deviceId, data);

  static Future<void> setupSdp({
    required SdpConfig config,
  }) =>
      _platform.setupSdp(config);

  static Future<void> closeSdp() => _platform.closeSdp();

  static Future<void> startScan() => _platform.startScan();

  static Future<void> stopScan() => _platform.stopScan();

  static Future<bool> isScanning() => _platform.isScanning();

  static Future<bool> pair(String address) => _platform.pair(address);

  static Future<void> unpair(String address) => _platform.unpair(address);

  static Future<List<BluetoothDevice>> getPairedDevices() =>
      _platform.getPairedDevices();

  static set onDeviceDiscovered(BluetoothDeviceCallback? callback) {
    UniversalBluetoothInterface.onDeviceDiscovered = callback;
  }

  static set onDeviceRemoved(BluetoothDeviceCallback? callback) {
    UniversalBluetoothInterface.onDeviceRemoved = callback;
  }

  static set onConnectionStateChanged(ConnectionChangeCallback? callback) {
    UniversalBluetoothInterface.onConnectionStateChanged = callback;
  }

  static set onGetReport(GetReportCallback? callback) {
    UniversalBluetoothInterface.onGetReport = callback;
  }

  static set onSdpServiceRegistrationUpdate(
      SdpServiceRegistrationUpdateCallback? callback) {
    UniversalBluetoothInterface.onSdpServiceRegistrationUpdate = callback;
  }

  static UniversalBluetoothInterface _defaultPlatform() {
    if (kIsWeb) return _DefaultImpl();
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return AccessoryManagerBluez.instance;
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return ExternalAccessory.instance;
    } else {
      return AccessoryManager.instance;
    }
  }
}

class _DefaultImpl extends UniversalBluetoothInterface {}
