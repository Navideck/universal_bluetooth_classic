import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/external_accessory.dart
// Generates File for IOS
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_bluetooth_classic',
    dartOut: 'lib/src/generated/external_accessory.g.dart',
    dartOptions: DartOptions(),
    swiftOut:
        'ios/universal_bluetooth_classic/Sources/universal_bluetooth_classic/ExternalAccessory.g.swift',
    swiftOptions: SwiftOptions(),
    debugGenerators: true,
  ),
)

/// Flutter -> Native
@HostApi()
abstract class ExternalAccessoryChannel {
  @asyncCallback
  void showBluetoothAccessoryPicker(
    List<String> withNames,
  );

  @asyncCallback
  void openSession(String protocolString);

  @asyncCallback
  void send(String protocolString, Uint8List data);

  @asyncCallback
  void closeSession(String? protocolString);
}

/// Native -> Flutter
@FlutterApi()
abstract class ExternalAccessoryCallbackChannel {
  @asyncCallback
  void onConnectionStateChanged(EAAccessory accessory, bool connected);

  @asyncCallback
  void onData(String protocolString, Uint8List data);
}

class EAAccessory {
  final bool isConnected;
  final int connectionID;
  final String manufacturer;
  final String name;
  final String modelNumber;
  final String serialNumber;
  final String firmwareRevision;
  final String hardwareRevision;
  final String dockType;
  final List<String> protocolStrings;

  EAAccessory({
    required this.isConnected,
    required this.connectionID,
    required this.manufacturer,
    required this.name,
    required this.modelNumber,
    required this.serialNumber,
    required this.firmwareRevision,
    required this.hardwareRevision,
    required this.dockType,
    required this.protocolStrings,
  });
}
