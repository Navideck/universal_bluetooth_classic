import 'package:universal_bluetooth_classic/src/universal_bluetooth_interface.dart';
import 'package:universal_bluetooth_classic/src/generated/external_accessory.g.dart';

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
  Future<void> disconnect([String? identifier]) =>
      _channel.closeEASession(identifier);
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
}
