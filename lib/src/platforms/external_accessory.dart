import 'dart:typed_data';

import 'package:universal_bluetooth_classic/src/generated/external_accessory.g.dart';
import 'package:universal_bluetooth_classic/src/universal_bluetooth_interface.dart';

class ExternalAccessory extends UniversalBluetoothInterface {
  static ExternalAccessory? _instance;
  static ExternalAccessory get instance => _instance ??= ExternalAccessory._();

  ExternalAccessory._() {
    ExternalAccessoryCallbackChannel.setUp(_CallbackHandler(this));
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
    BluetoothTransport? transport,
    String? serviceUuid,
  }) {
    switch (transport) {
      case null:
      case BluetoothTransport.externalAccessory:
        return _channel.openSession(deviceId);
      case BluetoothTransport.hid:
        throw UnsupportedError(
          'Bluetooth HID is not supported on iOS: the app cannot act as a HID '
          'host or device. Use the default (or BluetoothTransport.'
          'externalAccessory), which opens an External Accessory session for '
          'the protocol string.',
        );
      case BluetoothTransport.spp:
        throw UnsupportedError(
          'Serial (SPP/RFCOMM) connections are not supported on iOS: Apple '
          'exposes no RFCOMM socket or SDP API. MFi/iAP2 accessories carry data '
          'over RFCOMM, but are reached through their External Accessory protocol '
          'string, which uses the same send/onData byte-stream API.',
        );
    }
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
  _CallbackHandler(this._owner);

  final ExternalAccessory _owner;

  @override
  void onConnectionStateChanged(EAAccessory accessory, bool connected) {
    _owner.callbacks.onConnectionStateChanged?.call(
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
    _owner.callbacks.onData?.call(protocolString, data);
  }
}
