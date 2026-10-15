import 'package:flutter/foundation.dart';
import 'package:universal_bluetooth_classic/src/universal_bluetooth_interface.dart';

/// Decides which native transport handles a request and remembers the
/// transport each active device is connected with.
///
/// This is kept separate from the platform implementation so the routing rules
/// can be unit tested without the Pigeon channels.
class TransportRouter {
  /// Creates a router for [platform].
  ///
  /// The platform is passed in rather than read from [defaultTargetPlatform]
  /// here, so the only platform checks stay in `_defaultPlatform()` and the
  /// platform classes; see AGENTS.md.
  TransportRouter({required TargetPlatform platform}) : _platform = platform;

  final TargetPlatform _platform;
  final Map<String, BluetoothTransport> _active = {};

  /// Resolves a [BluetoothTransport.auto] request to the transport that
  /// platform actually implements.
  ///
  /// Windows has no Bluetooth HID implementation, so `auto` maps to the serial
  /// transport there; every other platform keeps HID as the default.
  /// Explicit [BluetoothTransport.hid] / [BluetoothTransport.spp] requests are
  /// returned unchanged.
  BluetoothTransport resolveConnect(BluetoothTransport requested) {
    switch (requested) {
      case BluetoothTransport.hid:
      case BluetoothTransport.spp:
        return requested;
      case BluetoothTransport.auto:
        return _platform == TargetPlatform.windows
            ? BluetoothTransport.spp
            : BluetoothTransport.hid;
    }
  }

  /// Records that [deviceId] is connected over [transport].
  void record(String deviceId, BluetoothTransport transport) {
    _active[deviceId] = transport;
  }

  /// The transport [deviceId] is currently connected with, or `null` when the
  /// device is not being tracked.
  BluetoothTransport? transportFor(String deviceId) => _active[deviceId];

  /// Forgets [deviceId], for example on an explicit disconnect or when a
  /// connect attempt fails.
  void forget(String deviceId) {
    _active.remove(deviceId);
  }
}
