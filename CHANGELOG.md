## 1.4.0

* Add `sendHidReport(deviceId, reportId, payload)` and
  `UniversalBluetooth.sendHidReport`. The report id is passed separately from
  the payload, matching Android's `BluetoothHidDevice.sendReport`; on macOS the
  plugin frames the HIDP DATA|INPUT header and report id itself. `send` keeps
  its raw/report-id-0 behaviour.
* Add `onReportRequest`, an additive HID get-report callback carrying the
  requested report id alongside device, type, and buffer size. A non-null reply
  takes precedence over `onGetReport`, which remains supported.
* Android: honour the Classic HID connect timeout. `connect` accepts
  `timeoutMillis` (15 s when omitted); `STATE_CONNECTING` is no longer reported
  as connected, and a timeout cancels the native request, settles the pending
  callback, and ignores the late confirmation.
* Android: settle a pending connect when the caller explicitly disconnects.
* Android: retry HID app registration after 5 seconds when `onAppStatusChanged`
  reports a loss, and report registration state to Dart.
* macOS: incoming L2CAP channels now create or attach to a session even when the
  app did not start the connect; a session is only reported connected once both
  the control and interrupt channels are open, and closing either channel tears
  the session down and reports the loss once. A partial open failure now closes
  the channel that did open.
* `UniversalBluetooth.connect` accepts an optional `timeout`.

## 1.3.1

* Windows: include `<winrt/Windows.Foundation.h>` and
  `<winrt/Windows.Foundation.Collections.h>` in `bluetooth_serial_manager.h` so
  the WinRT coroutine operators (`co_await`), `IClosable::Close`, and
  `IVectorView` collections compile cleanly with MSVC.

## 1.3.0

* macOS: keep a requested scan running. `IOBluetoothDeviceInquiry` only runs
  for `inquiryLength` seconds, so the plugin restarts it after a short delay
  until `stopScan` is called. Restarts that macOS throttles are retried, and
  `isScanning` reports whether a scan was requested, including the restart
  delay.
* macOS: resolve device names after an inquiry stops. macOS can report a
  found device with its address as the name; the plugin now issues remote name
  requests between inquiry rounds and re-emits the device when the name
  arrives, instead of relying on the system name cache.
* macOS: report each device once per scan and again only when its name
  changes, instead of re-emitting every device on every inquiry round. Pending
  name requests are dropped by `stopScan`, so no discovery events arrive after
  a scan is stopped.
* macOS: pair with a longer page timeout and up to three attempts. Classic
  `openConnection` can return `I/O Timeout` on the first page after discovery,
  especially when the device just switched from BLE to classic discoverable
  mode. Only timeouts are retried, so a rejected pairing or an unreachable
  device fails immediately instead of prompting again.
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
