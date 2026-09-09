import 'dart:async';
import 'dart:developer';

import 'package:bluez/bluez.dart';
import 'package:universal_bluetooth/src/universal_bluetooth_interface.dart';
import 'package:universal_bluetooth/src/generated/universal_bluetooth.g.dart';

class AccessoryManagerBluez extends UniversalBluetoothInterface {
  static AccessoryManagerBluez? _instance;
  static AccessoryManagerBluez get instance =>
      _instance ??= AccessoryManagerBluez._();
  AccessoryManagerBluez._();

  final BlueZClient _client = BlueZClient();
  bool isInitialized = false;
  Completer<void>? _initializationCompleter;
  BlueZAdapter? _activeAdapter;
  StreamSubscription? _deviceAdded;
  StreamSubscription? _deviceRemoved;
  final Map<String, BlueZDevice> _devices = {};

  @override
  Future<void> startScan() async {
    await _ensureInitialized();
    var adapter = _activeAdapter;
    if (adapter == null) {
      throw "Adapter not available";
    }
    await stopScan();
    _deviceAdded ??= _client.deviceAdded.listen(_onDeviceAdd);
    _deviceRemoved ??= _client.deviceRemoved.listen(_onDeviceRemoved);

    // Scans only for Bluetooth Classic devices
    adapter.setDiscoveryFilter(
      transport: "bredr",
    );
    await adapter.startDiscovery();
    for (var device in _client.devices) {
      _onDeviceAdd(device);
    }
  }

  @override
  Future<void> stopScan() async {
    await _ensureInitialized();
    try {
      _deviceAdded?.cancel();
      _deviceRemoved?.cancel();
      _deviceAdded = null;
      _deviceRemoved = null;
      if (_activeAdapter?.discovering == true) {
        await _activeAdapter?.stopDiscovery();
      }
    } catch (e) {
      log("stopScan error: $e");
    }
  }

  @override
  Future<bool> isScanning() async {
    await _ensureInitialized();
    return _activeAdapter?.discovering == true;
  }

  @override
  Future<bool> pair(String address) async {
    await _ensureInitialized();
    try {
      BlueZDevice device = _findDeviceById(address);
      await device.pair();
      return true;
    } catch (e) {
      log(e.toString());
      return false;
    }
  }

  @override
  Future<void> unpair(String address) async {
    await _ensureInitialized();
    BlueZDevice device = _findDeviceById(address);
    if (device.paired) {
      await _activeAdapter?.removeDevice(device);
    }
  }

  @override
  Future<List<BluetoothDevice>> getPairedDevices() async {
    await _ensureInitialized();
    return _client.devices
        .where((e) => e.paired)
        .map((device) => device.toBluetoothDevice())
        .toList();
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await _ensureInitialized();
    var device = _findDeviceById(deviceId);
    await device.disconnect();
  }

  void _onDeviceAdd(BlueZDevice device) {
    _devices[device.address] = device;
    UniversalBluetoothInterface.onBluetoothDeviceDiscover?.call(
      device.toBluetoothDevice(),
    );
  }

  void _onDeviceRemoved(BlueZDevice device) {
    _devices.remove(device.address);
  }

  BlueZDevice _findDeviceById(String deviceId) {
    BlueZDevice? bluezDevice = _devices[deviceId];
    if (bluezDevice != null) return bluezDevice;

    for (BlueZDevice device in _client.devices) {
      if (device.address == deviceId) return device;
    }

    throw Exception('Unknown deviceId:$deviceId');
  }

  Future<void> _ensureInitialized() async {
    if (isInitialized) return;

    if (_initializationCompleter != null) {
      await _initializationCompleter?.future;
      return;
    }

    _initializationCompleter = Completer<void>();

    try {
      await _client.connect();

      if (_client.adapters.isEmpty) {
        int attempts = 0;
        while (attempts < 10 && _client.adapters.isEmpty) {
          await Future.delayed(const Duration(milliseconds: 100));
          attempts++;
        }
      }

      if (_client.adapters.isEmpty) {
        throw Exception('Bluetooth adapter unavailable');
      }

      _activeAdapter ??= _client.adapters.first;

      _client.deviceAdded.listen(_onDeviceAdd);
      _client.deviceRemoved.listen(_onDeviceRemoved);

      isInitialized = true;
      _initializationCompleter?.complete();
      _initializationCompleter = null;
    } catch (e) {
      log('Error initializing: $e');
      _initializationCompleter?.completeError(e);
      await _client.close();
      rethrow;
    }
  }
}

extension _BlueZDeviceExtension on BlueZDevice {
  BluetoothDevice toBluetoothDevice() {
    return BluetoothDevice(
      name: name,
      address: address,
      paired: paired,
      rssi: rssi,
    );
  }
}
