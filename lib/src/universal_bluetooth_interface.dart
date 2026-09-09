import 'dart:typed_data';

import 'package:universal_bluetooth_classic/src/generated/bluetooth_hid_manager.g.dart';
import 'package:universal_bluetooth_classic/src/generated/external_accessory.g.dart';
import 'package:universal_bluetooth_classic/src/generated/universal_bluetooth.g.dart';

/// Platform interface for [UniversalBluetooth].
///
/// Extend this class to provide a custom or mocked platform implementation.
/// Unsupported operations throw [UnimplementedError] by default.
abstract class UniversalBluetoothInterface {
  /// Called when a Bluetooth device is discovered during a scan.
  static BluetoothDeviceCallback? onDeviceDiscovered;

  /// Called when a previously discovered Bluetooth device is removed.
  static BluetoothDeviceCallback? onDeviceRemoved;

  /// Called when the connection state of a device changes.
  static ConnectionChangeCallback? onConnectionStateChanged;

  /// Called when the platform requests a HID report.
  static GetReportCallback? onGetReport;

  /// Called when the SDP service registration status changes.
  static SdpServiceRegistrationUpdateCallback? onSdpServiceRegistrationUpdate;

  /// Opens the platform Bluetooth accessory picker, optionally filtered by
  /// [withNames].
  Future<void> showBluetoothAccessoryPicker({List<String>? withNames}) {
    throw UnimplementedError();
  }

  /// Connects to the Bluetooth HID device with the given [deviceId].
  Future<void> connect(String deviceId) {
    throw UnimplementedError();
  }

  /// Disconnects a device, or closes an iOS External Accessory session when
  /// [identifier] is a protocol string.
  Future<void> disconnect([String? identifier]) {
    throw UnimplementedError();
  }

  /// Registers a Bluetooth HID service using the given [config].
  Future<void> setupSdp(SdpConfig config) {
    throw UnimplementedError();
  }

  /// Closes the registered Bluetooth HID service.
  Future<void> closeSdp() {
    throw UnimplementedError();
  }

  /// Sends a HID [data] report to the connected device with the given
  /// [deviceId].
  Future<void> sendReport(String deviceId, Uint8List data) {
    throw UnimplementedError();
  }

  /// Starts scanning for nearby Bluetooth devices.
  Future<void> startScan() {
    throw UnimplementedError();
  }

  /// Stops the ongoing Bluetooth scan.
  Future<void> stopScan() {
    throw UnimplementedError();
  }

  /// Whether a Bluetooth scan is currently running.
  Future<bool> isScanning() {
    throw UnimplementedError();
  }

  /// Pairs the Bluetooth device with the given [address]. Returns whether the
  /// pairing succeeded.
  Future<bool> pair(String address) {
    throw UnimplementedError();
  }

  /// Unpairs the Bluetooth device with the given [address].
  Future<void> unpair(String address) {
    throw UnimplementedError();
  }

  /// Returns the list of already paired Bluetooth devices.
  Future<List<BluetoothDevice>> getPairedDevices() {
    throw UnimplementedError();
  }
}

/// Callback for device discovery and removal events.
typedef BluetoothDeviceCallback = void Function(BluetoothDevice device);

/// Callback for connection state changes.
typedef ConnectionChangeCallback = void Function(
  BluetoothConnectionEvent event,
);

/// The connection state of a Bluetooth device.
enum BluetoothConnectionState { connected, disconnected }

/// The source that triggered a connection state change.
enum BluetoothConnectionSource { hid, externalAccessory, system }

/// Describes a connection state change of a Bluetooth device.
class BluetoothConnectionEvent {
  /// Creates a connection state change event.
  const BluetoothConnectionEvent({
    required this.identifier,
    required this.state,
    required this.source,
    this.externalAccessory,
  });

  /// Identifier of the affected device.
  final String identifier;

  /// The new connection state.
  final BluetoothConnectionState state;

  /// The source that triggered the change.
  final BluetoothConnectionSource source;

  /// The iOS External Accessory value, when [source] is
  /// [BluetoothConnectionSource.externalAccessory].
  final EAAccessory? externalAccessory;
}

/// Callback for HID get-report requests.
typedef GetReportCallback = ReportReply? Function(
  String deviceId,
  ReportType type,
  int bufferSize,
);

/// Callback for SDP service registration status changes.
typedef SdpServiceRegistrationUpdateCallback = void Function(bool registered);
