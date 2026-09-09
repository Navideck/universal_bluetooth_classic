import 'dart:typed_data';

import 'package:universal_bluetooth/src/generated/bluetooth_hid_manager.g.dart';
import 'package:universal_bluetooth/src/generated/external_accessory.g.dart';
import 'package:universal_bluetooth/src/generated/universal_bluetooth.g.dart';

abstract class UniversalBluetoothInterface {
  static BluetoothDeviceCallback? onBluetoothDeviceDiscover;
  static BluetoothDeviceCallback? onBluetoothDeviceRemoved;
  static ConnectionChangeCallback? onConnectionStateChanged;
  static GetReportCallback? onGetReport;
  static SdpServiceRegistrationUpdateCallback? onSdpServiceRegistrationUpdate;

  Future<void> showBluetoothAccessoryPicker({
    List<String>? withNames,
  }) {
    throw UnimplementedError();
  }

  Future<void> connect(String deviceId) {
    throw UnimplementedError();
  }

  Future<void> disconnect([String? identifier]) {
    throw UnimplementedError();
  }

  Future<void> setupSdp(SdpConfig config) {
    throw UnimplementedError();
  }

  Future<void> closeSdp() {
    throw UnimplementedError();
  }

  Future<void> sendReport(String deviceId, Uint8List data) {
    throw UnimplementedError();
  }

  Future<void> startScan() {
    throw UnimplementedError();
  }

  Future<void> stopScan() {
    throw UnimplementedError();
  }

  Future<bool> isScanning() {
    throw UnimplementedError();
  }

  Future<bool> pair(String address) {
    throw UnimplementedError();
  }

  Future<void> unpair(String address) {
    throw UnimplementedError();
  }

  Future<List<BluetoothDevice>> getPairedDevices() {
    throw UnimplementedError();
  }
}

typedef BluetoothDeviceCallback = void Function(BluetoothDevice device);

typedef ConnectionChangeCallback = void Function(
  BluetoothConnectionEvent event,
);

enum BluetoothConnectionState { connected, disconnected }

enum BluetoothConnectionSource { hid, externalAccessory, system }

class BluetoothConnectionEvent {
  const BluetoothConnectionEvent({
    required this.identifier,
    required this.state,
    required this.source,
    this.externalAccessory,
  });

  final String identifier;
  final BluetoothConnectionState state;
  final BluetoothConnectionSource source;
  final EAAccessory? externalAccessory;
}

typedef GetReportCallback = ReportReply? Function(
    String deviceId, ReportType type, int bufferSize);

typedef SdpServiceRegistrationUpdateCallback = void Function(bool registered);
