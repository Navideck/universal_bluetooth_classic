import 'dart:typed_data';

import 'package:universal_bluetooth_classic/src/transport_router.dart';
import 'package:universal_bluetooth_classic/src/universal_bluetooth_interface.dart';
import 'package:universal_bluetooth_classic/src/generated/bluetooth_hid_manager.g.dart';
import 'package:universal_bluetooth_classic/src/generated/bluetooth_serial_manager.g.dart';
import 'package:universal_bluetooth_classic/src/generated/universal_bluetooth.g.dart';

class AccessoryManager extends UniversalBluetoothInterface {
  static AccessoryManager? _instance;
  static AccessoryManager get instance => _instance ??= AccessoryManager._();

  AccessoryManager._() {
    FlutterAccessoryCallbackChannel.setUp(_AccessoryCallbackHandler());
    BluetoothHidManagerCallbackChannel.setUp(_HidCallbackHandler());
    BluetoothSerialCallbackChannel.setUp(_SerialCallbackHandler());
  }

  static final _accessoryManagerChannel = FlutterAccessoryPlatformChannel();
  static final _hidManagerChannel = BluetoothHidManagerPlatformChannel();
  static final _serialChannel = BluetoothSerialPlatformChannel();

  /// Tracks the last transport each device was connected with, so [send] and
  /// [disconnect] can be routed to the matching native channel.
  ///
  /// The entry is overwritten on the next [connect] and removed by an explicit
  /// [disconnect]. It deliberately survives a spontaneous disconnect so a later
  /// [disconnect] or [send] still resolves to the transport the device used
  /// rather than falling back to HID.
  final TransportRouter _router = TransportRouter();

  @override
  Future<void> showBluetoothAccessoryPicker({
    List<String>? withNames,
  }) {
    return _accessoryManagerChannel
        .showBluetoothAccessoryPicker(withNames ?? []);
  }

  @override
  Future<void> disconnect([String? identifier]) {
    final deviceId = _requireIdentifier(identifier);
    final transport = _router.transportFor(deviceId);
    _router.forget(deviceId);
    if (transport == BluetoothTransport.spp) {
      return _serialChannel.disconnect(deviceId);
    }
    return _hidManagerChannel.disconnect(deviceId);
  }

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
  Future<void> connect(
    String deviceId, {
    BluetoothTransport transport = BluetoothTransport.auto,
    String? serviceUuid,
  }) async {
    final resolved = _router.resolveConnect(transport);
    _router.record(deviceId, resolved);
    try {
      if (resolved == BluetoothTransport.spp) {
        await _serialChannel.connect(deviceId, serviceUuid ?? sppServiceUuid);
      } else {
        await _hidManagerChannel.connect(deviceId);
      }
    } catch (_) {
      // A failed connect must not leave a transport behind, otherwise a later
      // send/disconnect for this device would be routed to the wrong channel.
      _router.forget(deviceId);
      rethrow;
    }
  }

  @override
  Future<void> send(String deviceId, Uint8List data) {
    if (_router.transportFor(deviceId) == BluetoothTransport.spp) {
      return _serialChannel.send(deviceId, data);
    }
    return _hidManagerChannel.send(deviceId, data);
  }

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
  void onData(String deviceId, Uint8List data) {
    UniversalBluetoothInterface.onData?.call(deviceId, data);
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

class _SerialCallbackHandler extends BluetoothSerialCallbackChannel {
  @override
  void onConnectionStateChanged(String deviceId, bool connected) {
    UniversalBluetoothInterface.onConnectionStateChanged?.call(
      BluetoothConnectionEvent(
        identifier: deviceId,
        state: connected
            ? BluetoothConnectionState.connected
            : BluetoothConnectionState.disconnected,
        source: BluetoothConnectionSource.spp,
      ),
    );
  }

  @override
  void onData(String deviceId, Uint8List data) {
    UniversalBluetoothInterface.onData?.call(deviceId, data);
  }
}
