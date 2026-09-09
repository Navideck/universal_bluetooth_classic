import 'dart:typed_data';

import 'package:universal_bluetooth_classic/src/universal_bluetooth_interface.dart';
import 'package:universal_bluetooth_classic/src/generated/bluetooth_hid_manager.g.dart';
import 'package:universal_bluetooth_classic/src/generated/universal_bluetooth.g.dart';

class AccessoryManager extends UniversalBluetoothInterface {
  static AccessoryManager? _instance;
  static AccessoryManager get instance => _instance ??= AccessoryManager._();

  AccessoryManager._() {
    FlutterAccessoryCallbackChannel.setUp(_AccessoryCallbackHandler());
    BluetoothHidManagerCallbackChannel.setUp(_HidCallbackHandler());
  }

  static final _accessoryManagerChannel = FlutterAccessoryPlatformChannel();
  static final _hidManagerChannel = BluetoothHidManagerPlatformChannel();

  @override
  Future<void> showBluetoothAccessoryPicker({
    List<String>? withNames,
  }) {
    return _accessoryManagerChannel
        .showBluetoothAccessoryPicker(withNames ?? []);
  }

  @override
  Future<void> disconnect([String? identifier]) =>
      _hidManagerChannel.disconnect(_requireIdentifier(identifier));

  @override
  Future<void> startScan() => _accessoryManagerChannel.startScan();

  @override
  Future<void> stopScan() => _accessoryManagerChannel.stopScan();

  @override
  Future<bool> isScanning() => _accessoryManagerChannel.isScanning();

  @override
  Future<bool> pair(String address) => _accessoryManagerChannel.pair(address);

  @override
  Future<void> unpair(String address) =>
      _accessoryManagerChannel.unpair(address);

  @override
  Future<List<BluetoothDevice>> getPairedDevices() =>
      _accessoryManagerChannel.getPairedDevices();

  @override
  Future<void> connect(String deviceId) => _hidManagerChannel.connect(deviceId);

  @override
  Future<void> sendReport(String deviceId, Uint8List data) =>
      _hidManagerChannel.sendReport(deviceId, data);

  @override
  Future<void> setupSdp(SdpConfig config) =>
      _hidManagerChannel.setupSdp(config);

  @override
  Future<void> closeSdp() => _hidManagerChannel.closeSdp();
}

String _requireIdentifier(String? identifier) =>
    identifier ?? (throw ArgumentError.notNull('identifier'));

// Handle callbacks from Native to Flutter
class _AccessoryCallbackHandler extends FlutterAccessoryCallbackChannel {
  @override
  void onDeviceDiscover(BluetoothDevice device) {
    UniversalBluetoothInterface.onDeviceDiscovered?.call(device);
  }

  @override
  void onDeviceRemoved(BluetoothDevice device) {
    UniversalBluetoothInterface.onDeviceRemoved?.call(device);
  }
}

class _HidCallbackHandler extends BluetoothHidManagerCallbackChannel {
  @override
  void onConnectionStateChanged(String deviceId, bool connected) {
    UniversalBluetoothInterface.onConnectionStateChanged?.call(
      BluetoothConnectionEvent(
        identifier: deviceId,
        state: connected
            ? BluetoothConnectionState.connected
            : BluetoothConnectionState.disconnected,
        source: BluetoothConnectionSource.hid,
      ),
    );
  }

  @override
  ReportReply? onGetReport(String deviceId, ReportType type, int bufferSize) {
    return UniversalBluetoothInterface.onGetReport?.call(
      deviceId,
      type,
      bufferSize,
    );
  }

  @override
  void onSdpServiceRegistrationUpdate(bool registered) {
    UniversalBluetoothInterface.onSdpServiceRegistrationUpdate?.call(
      registered,
    );
  }
}
