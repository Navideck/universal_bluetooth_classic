## Unreleased

* macOS: keep a requested scan running. `IOBluetoothDeviceInquiry` only runs
  for `inquiryLength` seconds, so the plugin restarts it after a short delay
  until `stopScan` is called. Restarts that macOS throttles are retried, and
  `isScanning` reports whether a scan was requested, including the restart
  delay.
* macOS: resolve device names after an inquiry stops. macOS can report a
  found device with its address as the name; the plugin now issues remote name
  requests between inquiry rounds and re-emits the device when the name
  arrives, instead of relying on the system name cache.
* macOS: pair with a longer page timeout and up to three attempts. Classic
  `openConnection` can return `I/O Timeout` on the first page after discovery,
  especially when the device just switched from BLE to classic discoverable
  mode.
* macOS: propagate `IOBluetoothDeviceInquiry.start()` failures from
  `startScan` instead of silently doing nothing.

## 1.2.0

* Add a generic serial (SPP/RFCOMM) transport on Android, macOS, and Windows.
  `connect` takes an optional `BluetoothTransport` and an optional `serviceUuid`;
  bytes are exchanged through the existing `send` / `onData` API. The
  `BluetoothTransport` enum has `hid`, `spp`, and `externalAccessory` members;
  omitting `transport` selects the platform default — HID on Android and macOS,
  serial (SPP/RFCOMM) on Windows, and an External Accessory session on iOS.
  Windows gains data-transport support (`connect` / `send` / `onData` /
  `disconnect`) through this transport; Bluetooth HID remains unimplemented
  there, so the default resolves to the serial transport on Windows.
* Connection state events for the serial transport carry the new
  `BluetoothConnectionSource.spp` value.
* `connect` rejects a second concurrent connection to the same device with a
  `StateError` instead of overwriting the transport the first one recorded, and
  `disconnect` waits for an in-flight connect so the connection it opens is
  actually closed. `closeSdp` now throws `UnsupportedError` on platforms
  without SDP registration (Windows) instead of reaching an unregistered
  channel.
* Add an optional `bluez` dependency lower bound of `^0.9.0` for the Linux
  implementation.
* Note that adding the optional `transport` and `serviceUuid` parameters to
  `connect` is a source-breaking change for custom `UniversalBluetoothInterface`
  implementations.
* Migrate the Pigeon definitions and generated bindings to Pigeon 29.0.10.
  Because this plugin targets long-established platform APIs, the host and
  callback methods use Pigeon's `@asyncCallback` style: the native side stays
  callback-based, so no Kotlin coroutines dependency and no Swift concurrency
  (and no iOS deployment-target bump) are required.
* Replace the `static` callback fields on `UniversalBluetoothInterface` with a
  per-implementation `UniversalBluetoothCallbacks` registry. The
  `UniversalBluetooth.onXxx` setters are unchanged, but a custom
  `UniversalBluetoothInterface` implementation must now forward its events to
  `callbacks` instead of the removed statics. This is a source-breaking change
  for custom implementations.
* Give Android and macOS SDP registration their own Pigeon channels
  (`AndroidSdpChannel`, `MacSdpChannel`) so each platform's generated code
  carries only its own config. The public `SdpConfig` / `MacSdpConfig` /
  `AndroidSdpConfig` API is unchanged.
* Add a `meta` dependency, which the Pigeon 29 generated Dart bindings import
  for their `@immutable` / `@protected` / `@visibleForTesting` annotations.

## 1.1.0

* Add a unified byte-stream API. `connect`, `send`, and the new `onData`
  callback exchange bytes with a connected device. The HID `sendReport` method
  is replaced by `send`.
* Add iOS External Accessory data support. `connect(protocolString)` opens an
  `EASession`, `send` writes to its output stream, and `onData` receives bytes
  from its input stream.
* Deliver `onData` on Android and macOS by forwarding the bytes the connected
  HID device already sends.
* Fix iOS `disconnect` hanging until the accessory physically disconnected. It
  now closes the session and completes immediately, and closes every open
  session when the protocol string is omitted.
* Fix iOS External Accessory connect/disconnect events never firing. The Pigeon
  `EAAccessory` struct shadowed the framework class, so the notification
  handlers always failed to cast and returned early.

## 1.0.0

* Fix `showBluetoothAccessoryPicker` not presenting on iOS apps that use the
  `UIScene` lifecycle (iOS 13–26.4). The plugin now presents the External
  Accessory picker from the active scene.
* Fix the iOS example app's scene manifest key so it runs under the `UIScene`
  lifecycle.

## 0.2.0

* Replace the iOS-only `closeEASession` API with the unified `disconnect` API.
  The identifier is optional for iOS External Accessory sessions.
* Replace the iOS-only `accessoryConnected` and `accessoryDisconnected`
  callbacks with typed, cross-platform `BluetoothConnectionEvent` values from
  `onConnectionStateChanged`.
* Add iOS External Accessory and Linux BlueZ connection events.

## 0.1.0

* Initial release as `universal_bluetooth`.
