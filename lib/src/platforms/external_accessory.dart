import 'package:universal_bluetooth/src/universal_bluetooth_interface.dart';
import 'package:universal_bluetooth/src/generated/external_accessory.g.dart';

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
  Future<void> closeEASession([String? protocolString]) =>
      _channel.closeEASession(protocolString);
}

// Handle callbacks from Native to Flutter
class _CallbackHandler extends ExternalAccessoryCallbackChannel {
  @override
  void accessoryConnected(EAAccessory accessory) {
    UniversalBluetoothInterface.accessoryConnected?.call(accessory);
  }

  @override
  void accessoryDisconnected(EAAccessory accessory) {
    UniversalBluetoothInterface.accessoryDisconnected?.call(accessory);
  }
}
