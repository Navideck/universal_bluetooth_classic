import 'dart:typed_data';

import 'package:universal_bluetooth/src/universal_bluetooth_interface.dart';
import 'package:universal_bluetooth/src/generated/bluetooth_hid_manager.g.dart';
import 'package:universal_bluetooth/src/generated/universal_bluetooth.g.dart';

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
  Future<void> disconnect(String deviceId) =>
      _hidManagerChannel.disconnect(deviceId);

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

// Handle callbacks from Native to Flutter
class _AccessoryCallbackHandler extends FlutterAccessoryCallbackChannel {
  @override
  void onDeviceDiscover(BluetoothDevice device) {
    UniversalBluetoothInterface.onBluetoothDeviceDiscover?.call(device);
  }

  @override
  void onDeviceRemoved(BluetoothDevice device) {
    UniversalBluetoothInterface.onBluetoothDeviceRemoved?.call(device);
  }
}

class _HidCallbackHandler extends BluetoothHidManagerCallbackChannel {
  @override
  void onConnectionStateChanged(String deviceId, bool connected) {
    UniversalBluetoothInterface.onConnectionStateChanged
        ?.call(deviceId, connected);
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
