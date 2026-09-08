import 'package:bluetooth_accessory_manager/src/bluetooth_accessory_manager_interface.dart';
import 'package:bluetooth_accessory_manager/src/generated/external_accessory.g.dart';

class ExternalAccessory extends BluetoothAccessoryManagerInterface {
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
    BluetoothAccessoryManagerInterface.accessoryConnected?.call(accessory);
  }

  @override
  void accessoryDisconnected(EAAccessory accessory) {
    BluetoothAccessoryManagerInterface.accessoryDisconnected?.call(accessory);
  }
}
