## Unreleased

* Add a generic serial (SPP/RFCOMM) transport on Android, macOS, and Windows.
  `connect` takes a `BluetoothTransport` and an optional `serviceUuid`; bytes
  are exchanged through the existing `send` / `onData` API, and connection
  events carry `BluetoothConnectionSource.spp`. Windows gains data-transport
  support (`connect` / `send` / `onData` / `disconnect`) through this transport;
  Bluetooth HID remains unimplemented there, so `BluetoothTransport.auto`
  resolves to the serial transport on Windows.
* Note that adding the optional `transport` and `serviceUuid` parameters to
  `connect` is a source-breaking change for custom `UniversalBluetoothInterface`
  implementations.

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
