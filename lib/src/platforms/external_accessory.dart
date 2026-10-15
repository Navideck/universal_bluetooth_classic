import 'dart:typed_data';

import 'package:universal_bluetooth_classic/src/generated/external_accessory.g.dart';
import 'package:universal_bluetooth_classic/src/universal_bluetooth_interface.dart';

class ExternalAccessory extends UniversalBluetoothInterface {
  static ExternalAccessory? _instance;
  static ExternalAccessory get instance => _instance ??= ExternalAccessory._();

  ExternalAccessory._() {
    ExternalAccessoryCallbackChannel.setUp(_CallbackHandler());
  }

  static final _channel = ExternalAccessoryChannel();

  @override
  Future<void> showBluetoothAccessoryPicker({
    List<String>? withNames,
  }) {
    return _channel.showBluetoothAccessoryPicker(withNames ?? []);
  }

  @override
  Future<void> connect(
    String deviceId, {
    BluetoothTransport transport = BluetoothTransport.auto,
    String? serviceUuid,
  }) {
    if (transport == BluetoothTransport.spp) {
      throw UnsupportedError(
        'Serial (SPP/RFCOMM) connections are not supported on iOS. '
        'Use an External Accessory protocol string instead.',
      );
    }
    return _channel.openSession(deviceId);
  }

  @override
  Future<void> send(String deviceId, Uint8List data) =>
      _channel.send(deviceId, data);

  @override
  Future<void> disconnect([String? identifier]) =>
      _channel.closeSession(identifier);
}

// Handle callbacks from Native to Flutter
class _CallbackHandler extends ExternalAccessoryCallbackChannel {
  @override
  void onConnectionStateChanged(EAAccessory accessory, bool connected) {
    UniversalBluetoothInterface.onConnectionStateChanged?.call(
      BluetoothConnectionEvent(
        identifier: accessory.connectionID.toString(),
        state: connected
            ? BluetoothConnectionState.connected
            : BluetoothConnectionState.disconnected,
        source: BluetoothConnectionSource.externalAccessory,
        externalAccessory: accessory,
      ),
    );
  }

  @override
  void onData(String protocolString, Uint8List data) {
    UniversalBluetoothInterface.onData?.call(protocolString, data);
  }
}
