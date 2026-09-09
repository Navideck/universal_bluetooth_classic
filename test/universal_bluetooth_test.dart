import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_bluetooth_classic/universal_bluetooth_classic.dart';

void main() {
  late _FakeUniversalBluetooth platform;

  setUp(() {
    platform = _FakeUniversalBluetooth();
    UniversalBluetooth.setInstance(platform);
  });

  tearDown(() {
    UniversalBluetooth.setInstance(null);
    UniversalBluetooth.onDeviceDiscovered = null;
    UniversalBluetooth.onDeviceRemoved = null;
    UniversalBluetooth.onConnectionStateChanged = null;
    UniversalBluetooth.onGetReport = null;
    UniversalBluetooth.onSdpServiceRegistrationUpdate = null;
  });

  test('delegates commands and arguments to the platform implementation',
      () async {
    final report = Uint8List.fromList([1, 2, 3]);
    final config = SdpConfig();

    await UniversalBluetooth.showBluetoothAccessoryPicker(
      withNames: ['Keyboard'],
    );
    await UniversalBluetooth.connect('device-id');
    await UniversalBluetooth.disconnect();
    await UniversalBluetooth.sendReport('device-id', report);
    await UniversalBluetooth.setupSdp(config: config);
    await UniversalBluetooth.closeSdp();
    await UniversalBluetooth.startScan();
    await UniversalBluetooth.stopScan();
    await UniversalBluetooth.unpair('address');

    expect(platform.pickerNames, ['Keyboard']);
    expect(platform.connectedDeviceId, 'device-id');
    expect(platform.disconnectCalled, isTrue);
    expect(platform.disconnectedIdentifier, isNull);
    expect(platform.reportDeviceId, 'device-id');
    expect(platform.report, same(report));
    expect(platform.sdpConfig, same(config));
    expect(platform.closeSdpCalled, isTrue);
    expect(platform.startScanCalled, isTrue);
    expect(platform.stopScanCalled, isTrue);
    expect(platform.unpairedAddress, 'address');
  });

  test('returns query results from the platform implementation', () async {
    expect(await UniversalBluetooth.isScanning(), isTrue);
    expect(await UniversalBluetooth.pair('address'), isTrue);
    expect(platform.pairedAddress, 'address');
    expect(
      await UniversalBluetooth.getPairedDevices(),
      same(platform.pairedDevices),
    );
  });

  test('registers public callbacks', () {
    BluetoothConnectionEvent? receivedEvent;
    final event = BluetoothConnectionEvent(
      identifier: 'device-id',
      state: BluetoothConnectionState.connected,
      source: BluetoothConnectionSource.hid,
    );

    UniversalBluetooth.onConnectionStateChanged = (value) {
      receivedEvent = value;
    };
    UniversalBluetoothInterface.onConnectionStateChanged?.call(event);

    expect(receivedEvent, same(event));
  });
}

class _FakeUniversalBluetooth extends UniversalBluetoothInterface {
  final pairedDevices = <BluetoothDevice>[
    BluetoothDevice(
      address: 'address',
      name: 'Keyboard',
      paired: true,
      rssi: -40,
    ),
  ];

  List<String>? pickerNames;
  String? connectedDeviceId;
  bool disconnectCalled = false;
  String? disconnectedIdentifier;
  String? reportDeviceId;
  Uint8List? report;
  SdpConfig? sdpConfig;
  bool closeSdpCalled = false;
  bool startScanCalled = false;
  bool stopScanCalled = false;
  String? pairedAddress;
  String? unpairedAddress;

  @override
  Future<void> showBluetoothAccessoryPicker({List<String>? withNames}) async {
    pickerNames = withNames;
  }

  @override
  Future<void> connect(String deviceId) async {
    connectedDeviceId = deviceId;
  }

  @override
  Future<void> disconnect([String? identifier]) async {
    disconnectCalled = true;
    disconnectedIdentifier = identifier;
  }

  @override
  Future<void> sendReport(String deviceId, Uint8List data) async {
    reportDeviceId = deviceId;
    report = data;
  }

  @override
  Future<void> setupSdp(SdpConfig config) async {
    sdpConfig = config;
  }

  @override
  Future<void> closeSdp() async {
    closeSdpCalled = true;
  }

  @override
  Future<void> startScan() async {
    startScanCalled = true;
  }

  @override
  Future<void> stopScan() async {
    stopScanCalled = true;
  }

  @override
  Future<bool> isScanning() async => true;

  @override
  Future<bool> pair(String address) async {
    pairedAddress = address;
    return true;
  }

  @override
  Future<void> unpair(String address) async {
    unpairedAddress = address;
  }

  @override
  Future<List<BluetoothDevice>> getPairedDevices() async => pairedDevices;
}
