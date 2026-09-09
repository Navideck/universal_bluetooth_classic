import 'package:flutter/foundation.dart';
import 'package:universal_bluetooth_classic/universal_bluetooth_classic.dart';
import 'package:universal_bluetooth_classic/src/platforms/accessory_manager.dart';
import 'package:universal_bluetooth_classic/src/platforms/accessory_manager_bluez.dart';
import 'package:universal_bluetooth_classic/src/platforms/external_accessory.dart';

/// The main API for discovering, pairing, and connecting to Bluetooth
/// Classic accessories and Apple External Accessory devices.
///
/// All methods delegate to the active [UniversalBluetoothInterface]. Call
/// [setInstance] with a custom implementation (for example a mock in tests)
/// to replace the default platform implementation.
class UniversalBluetooth {
  /// Default platform accessor.
  static UniversalBluetoothInterface? _platformInstance;
  static UniversalBluetoothInterface get _platform =>
      _platformInstance ??= _defaultPlatform();

  /// Set custom platform specific implementation (e.g. for testing).
  static void setInstance(UniversalBluetoothInterface? instance) {
    _platformInstance = instance;
  }

  /// Opens the platform Bluetooth accessory picker.
  ///
  /// [withNames] optionally restricts the picker to accessories with the
  /// given names. On iOS this presents the External Accessory picker, the
  /// only supported way to pair Bluetooth Classic MFi devices.
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

  /// Connects to the Bluetooth HID device with the given [deviceId].
  static Future<void> connect(String deviceId) => _platform.connect(deviceId);

  /// Sends a HID [data] report to the connected device with the given
  /// [deviceId].
  static Future<void> sendReport(String deviceId, Uint8List data) =>
      _platform.sendReport(deviceId, data);

  /// Registers a Bluetooth HID service using the given platform-specific
  /// [config].
  static Future<void> setupSdp({required SdpConfig config}) =>
      _platform.setupSdp(config);

  /// Closes the registered Bluetooth HID service.
  static Future<void> closeSdp() => _platform.closeSdp();

  /// Starts scanning for nearby Bluetooth devices.
  static Future<void> startScan() => _platform.startScan();

  /// Stops the ongoing Bluetooth scan.
  static Future<void> stopScan() => _platform.stopScan();

  /// Whether a Bluetooth scan is currently running.
  static Future<bool> isScanning() => _platform.isScanning();

  /// Pairs the Bluetooth device with the given [address]. Returns whether the
  /// pairing succeeded.
  static Future<bool> pair(String address) => _platform.pair(address);

  /// Unpairs the Bluetooth device with the given [address].
  static Future<void> unpair(String address) => _platform.unpair(address);

  /// Returns the list of already paired Bluetooth devices.
  static Future<List<BluetoothDevice>> getPairedDevices() =>
      _platform.getPairedDevices();

  /// Called when a Bluetooth device is discovered during a scan.
  static set onDeviceDiscovered(BluetoothDeviceCallback? callback) {
    UniversalBluetoothInterface.onDeviceDiscovered = callback;
  }

  /// Called when a previously discovered Bluetooth device is removed.
  static set onDeviceRemoved(BluetoothDeviceCallback? callback) {
    UniversalBluetoothInterface.onDeviceRemoved = callback;
  }

  /// Called when the connection state of a device changes.
  static set onConnectionStateChanged(ConnectionChangeCallback? callback) {
    UniversalBluetoothInterface.onConnectionStateChanged = callback;
  }

  /// Called when the platform requests a HID report.
  static set onGetReport(GetReportCallback? callback) {
    UniversalBluetoothInterface.onGetReport = callback;
  }

  /// Called when the SDP service registration status changes.
  static set onSdpServiceRegistrationUpdate(
    SdpServiceRegistrationUpdateCallback? callback,
  ) {
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
