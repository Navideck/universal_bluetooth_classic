import 'package:flutter/foundation.dart';
import 'package:universal_bluetooth_classic/src/sdp_config.dart';
import 'package:universal_bluetooth_classic/src/transport_router.dart';
import 'package:universal_bluetooth_classic/src/universal_bluetooth_interface.dart';
import 'package:universal_bluetooth_classic/src/generated/android_sdp.g.dart';
import 'package:universal_bluetooth_classic/src/generated/bluetooth_hid_manager.g.dart';
import 'package:universal_bluetooth_classic/src/generated/bluetooth_serial_manager.g.dart';
import 'package:universal_bluetooth_classic/src/generated/mac_sdp.g.dart';
import 'package:universal_bluetooth_classic/src/generated/universal_bluetooth.g.dart';

class AccessoryManager extends UniversalBluetoothInterface {
  static AccessoryManager? _instance;
  static AccessoryManager get instance => _instance ??= AccessoryManager._();

  AccessoryManager._() {
    FlutterAccessoryCallbackChannel.setUp(_AccessoryCallbackHandler(this));
    BluetoothHidManagerCallbackChannel.setUp(_HidCallbackHandler(this));
    BluetoothSerialCallbackChannel.setUp(_SerialCallbackHandler(this));
  }

  static final _accessoryManagerChannel = FlutterAccessoryPlatformChannel();
  static final _hidManagerChannel = BluetoothHidManagerPlatformChannel();
  static final _serialChannel = BluetoothSerialPlatformChannel();
  static final _androidSdpChannel = AndroidSdpChannel();
  static final _macSdpChannel = MacSdpChannel();

  /// Tracks the last transport each device was connected with, so [send] and
  /// [disconnect] can be routed to the matching native channel.
  ///
  /// The entry is overwritten on the next [connect] and removed by an explicit
  /// [disconnect]. It deliberately survives a spontaneous disconnect so a later
  /// [disconnect] or [send] still resolves to the transport the device used
  /// rather than falling back to HID.
  ///
  /// The platform is read here, inside a platform class, so [TransportRouter]
  /// itself stays free of platform checks.
  final TransportRouter _router = TransportRouter(
    platform: defaultTargetPlatform,
  );

  /// Connects that have not settled yet, keyed by device ID.
  ///
  /// A second [connect] for a device that already has one in flight is rejected
  /// rather than started: starting it would overwrite the transport the first
  /// connect recorded, and a later [send] / [disconnect] would then be routed
  /// to the wrong channel (the platforms reject the duplicate anyway with an
  /// "in progress" error). [disconnect] waits for a pending connect so its
  /// close lands after the socket the connect leaves behind exists.
  final Map<String, Future<void>> _pendingConnects = {};

  @override
  Future<void> showBluetoothAccessoryPicker({
    List<String>? withNames,
  }) {
    return _accessoryManagerChannel
        .showBluetoothAccessoryPicker(withNames ?? []);
  }

  @override
  Future<void> disconnect([String? identifier]) async {
    final deviceId = _requireIdentifier(identifier);
    // Capture the transport before waiting: a concurrent connect that fails
    // clears the recorded transport, and this close still has to reach the
    // channel the connect started on.
    final transport = _router.transportFor(deviceId);
    final pending = _pendingConnects[deviceId];
    if (pending != null) {
      // Disconnecting while a connect is in flight would otherwise be a no-op,
      // leaving the connection the connect opens behind. Let it settle first.
      try {
        await pending;
      } catch (_) {
        // The connect failed, so there is nothing to close.
      }
    }
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
    BluetoothTransport? transport,
    String? serviceUuid,
    Duration? timeout,
  }) {
    if (_pendingConnects.containsKey(deviceId)) {
      return Future<void>.error(
        StateError('A connection to $deviceId is already in progress'),
      );
    }
    final future = _connect(
      deviceId,
      transport: transport,
      serviceUuid: serviceUuid,
      timeout: timeout,
    );
    _pendingConnects[deviceId] = future;
    return future.whenComplete(() {
      if (identical(_pendingConnects[deviceId], future)) {
        _pendingConnects.remove(deviceId);
      }
    });
  }

  Future<void> _connect(
    String deviceId, {
    BluetoothTransport? transport,
    String? serviceUuid,
    Duration? timeout,
  }) async {
    final resolved = _router.resolveConnect(transport);
    _router.record(deviceId, resolved);
    try {
      switch (resolved) {
        case BluetoothTransport.hid:
          await _hidManagerChannel.connect(deviceId, timeout?.inMilliseconds);
        case BluetoothTransport.spp:
          await _serialChannel.connect(deviceId, serviceUuid ?? sppServiceUuid);
        case BluetoothTransport.externalAccessory:
          throw UnsupportedError(
            'BluetoothTransport.externalAccessory is only supported on iOS.',
          );
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
  Future<void> sendHidReport(String deviceId, int reportId, Uint8List data) {
    if (_router.transportFor(deviceId) != BluetoothTransport.hid) {
      throw UnsupportedError(
        'HID reports with a report id require a Bluetooth HID connection.',
      );
    }
    return _hidManagerChannel.sendHidReport(deviceId, reportId, data);
  }

  @override
  Future<void> setupSdp(SdpConfig config) {
    // Each platform has its own SDP channel, so the union in [SdpConfig] is
    // resolved here, inside a platform class, keeping the check out of shared
    // code; see AGENTS.md.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final androidConfig = config.androidSdpConfig;
        if (androidConfig == null) {
          throw ArgumentError.notNull('config.androidSdpConfig');
        }
        return _androidSdpChannel.setupSdp(androidConfig);
      case TargetPlatform.macOS:
        final macConfig = config.macSdpConfig;
        if (macConfig == null) {
          throw ArgumentError.notNull('config.macSdpConfig');
        }
        return _macSdpChannel.setupSdp(macConfig);
      default:
        throw UnsupportedError(
          'SDP service registration is not supported on '
          '${defaultTargetPlatform.name}.',
        );
    }
  }

  @override
  Future<void> closeSdp() {
    // Mirrors [setupSdp]: the HID channel that owns the SDP service only exists
    // on Android and macOS, so fail clearly elsewhere instead of reaching an
    // unregistered channel.
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.macOS:
        return _hidManagerChannel.closeSdp();
      default:
        throw UnsupportedError(
          'SDP service registration is not supported on '
          '${defaultTargetPlatform.name}.',
        );
    }
  }
}

String _requireIdentifier(String? identifier) =>
    identifier ?? (throw ArgumentError.notNull('identifier'));

// Handle callbacks from Native to Flutter
class _AccessoryCallbackHandler extends FlutterAccessoryCallbackChannel {
  _AccessoryCallbackHandler(this._owner);

  final AccessoryManager _owner;

  @override
  Future<void> onDeviceDiscover(BluetoothDevice device) async {
    _owner.callbacks.onDeviceDiscovered?.call(device);
  }

  @override
  Future<void> onDeviceRemoved(BluetoothDevice device) async {
    _owner.callbacks.onDeviceRemoved?.call(device);
  }
}

class _HidCallbackHandler extends BluetoothHidManagerCallbackChannel {
  _HidCallbackHandler(this._owner);

  final AccessoryManager _owner;

  @override
  Future<void> onConnectionStateChanged(String deviceId, bool connected) async {
    if (connected) {
      _owner._router.record(deviceId, BluetoothTransport.hid);
    }
    _owner.callbacks.onConnectionStateChanged?.call(
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
  Future<void> onData(String deviceId, Uint8List data) async {
    _owner.callbacks.onData?.call(deviceId, data);
  }

  @override
  Future<ReportReply?> onGetReport(
    String deviceId,
    ReportType type,
    int bufferSize,
  ) async {
    return _owner.callbacks.onGetReport?.call(deviceId, type, bufferSize);
  }

  @override
  Future<ReportReply?> onReportRequest(
    String deviceId,
    ReportType type,
    int reportId,
    int bufferSize,
  ) async {
    // The report-id-aware callback wins when it answers; otherwise the legacy
    // callback gets its turn on the native side.
    return _owner.callbacks.onReportRequest?.call(
      HidReportRequest(
        deviceId: deviceId,
        type: type,
        reportId: reportId,
        bufferSize: bufferSize,
      ),
    );
  }

  @override
  Future<void> onSdpServiceRegistrationUpdate(bool registered) async {
    _owner.callbacks.onSdpServiceRegistrationUpdate?.call(registered);
  }
}

class _SerialCallbackHandler extends BluetoothSerialCallbackChannel {
  _SerialCallbackHandler(this._owner);

  final AccessoryManager _owner;

  @override
  Future<void> onConnectionStateChanged(String deviceId, bool connected) async {
    _owner.callbacks.onConnectionStateChanged?.call(
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
  Future<void> onData(String deviceId, Uint8List data) async {
    _owner.callbacks.onData?.call(deviceId, data);
  }
}
