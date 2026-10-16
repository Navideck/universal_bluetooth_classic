# Universal Bluetooth Classic Agent Guidelines

This repository provides a unified cross-platform Flutter plugin (`universal_bluetooth_classic`) for Bluetooth Classic HID, Bluetooth Classic serial (SPP/RFCOMM), and Apple External Accessory, targeting Android, iOS, macOS, Windows, and Linux. Bluetooth Low Energy (BLE) is out of scope.

For environment setup, the checks to run before opening a PR, Pigeon regeneration commands, PR conventions, and licensing, follow [CONTRIBUTING.md](CONTRIBUTING.md). This file records the invariants an agent must not break.

## Platform routing (critical)

`UniversalBluetooth` is a static facade in `lib/src/universal_bluetooth.dart` that delegates to `UniversalBluetoothInterface` (`lib/src/universal_bluetooth_interface.dart`). The active implementation is chosen in one place, `_defaultPlatform()`:

| Target platform | Implementation | Native transport |
| :-- | :-- | :-- |
| Linux | `AccessoryManagerBluez` | BlueZ |
| iOS | `ExternalAccessory` | Apple External Accessory |
| Android, macOS, Windows | `AccessoryManager` | Bluetooth HID and/or serial (SPP/RFCOMM) |
| Web | `_DefaultImpl` | none |

Do not add platform checks outside `_defaultPlatform()` and the platform classes.

`TransportRouter` (`lib/src/transport_router.dart`) holds `AccessoryManager`'s routing rules and takes the `TargetPlatform` as a constructor argument precisely so it contains no platform check of its own; the platform class supplies `defaultTargetPlatform`. Keep it that way when adding transports.

Note: `AccessoryManager` handles the HID channel, the serial channel, and the per-platform SDP channels (`AndroidSdpChannel` / `MacSdpChannel`). The Windows plugin implements the accessory channel (discovery, pairing, picker) and the serial (SPP/RFCOMM) channel, but not the HID channel: `BluetoothTransport.auto` resolves to the serial transport on Windows (see `TransportRouter`), while `setupSdp` / `closeSdp` and HID connections are unsupported there (`AccessoryManager.setupSdp` throws `UnsupportedError`). Keep the README matrix accurate.

## SDP configuration is split per platform

Android and macOS register their HID service through separate Pigeon channels, each defined in its own input file: `pigeon/android_sdp.dart` (`AndroidSdpConfig`, Kotlin + Dart output only) and `pigeon/mac_sdp.dart` (`MacSdpConfig`, Swift + Dart output only). This is deliberate: Pigeon emits every class into every configured output and validates Swift for a field named `description`, so an Android config type must never share a file with `swiftOut`. The public `SdpConfig` union (`lib/src/sdp_config.dart`) is hand-written Dart that keeps one cross-platform call site; `AccessoryManager.setupSdp` resolves it to the platform's channel. Do not move these types back into `pigeon/bluetooth_hid_manager.dart`.

## `identifier` is overloaded across platforms (critical)

The same `String identifier` passed to `connect`, `send`, `disconnect`, and delivered by `onData` means different things per platform:

| API | Android / macOS (HID) | iOS (External Accessory) |
| :-- | :-- | :-- |
| `connect` | device ID (MAC address) | protocol string — opens an `EASession` |
| `send` | HID output report | `EASession` output stream |
| `onData` | bytes from the peer (device ID) | bytes from the session (protocol string) |
| `disconnect` | device ID | optional protocol string; omitted closes **every** open session |

On Linux only `disconnect` (BlueZ) is implemented; the data APIs are unsupported.

For serial (SPP/RFCOMM) connections (`transport: BluetoothTransport.spp`) on Android, macOS, and Windows, the identifier is the device address (MAC), the same vocabulary as HID.

Do not assume the identifier is a MAC address or a protocol string in shared Dart code. Keep the distinction inside the platform implementations and in the README.

## The HID role differs by platform

- Android runs the app as a HID **device** (`BluetoothHidDevice`); `onSetReport` and `onInterruptData` carry bytes sent by the peer and are forwarded to `onData`.
- macOS runs as a HID **host**; input reports arrive on the L2CAP interrupt channel and are forwarded to `onData`.

Both represent "data received from the connected device". Keep the forwarding consistent across the two if you touch either.

## iOS: the Pigeon `EAAccessory` struct shadows the framework class (critical)

`pigeon/external_accessory.dart` generates a Swift struct named `EAAccessory` (`ExternalAccessory.g.swift`) that collides with the `ExternalAccessory.EAAccessory` framework class. In host Swift code, `as? EAAccessory` resolves to the generated struct and **always fails**, so notification casts silently return `nil`.

Always qualify the framework type when reading notifications or creating sessions:

```swift
guard let accessory = notification.userInfo?[EAAccessoryKey] as? ExternalAccessory.EAAccessory else { return }
```

This was the root cause of "iOS connect/disconnect events never fired".

## iOS session lifecycle

`EASessionController` (`ios/universal_bluetooth_classic/Sources/universal_bluetooth_classic/EASessionController.swift`) owns one `EASession`:

- Streams are scheduled on the main run loop in `.common` mode (so callbacks fire during tracking/scrolls), writes are buffered until the output stream has space, and the input stream is drained in 1024-byte chunks.
- `connect` (`openSession`) resolves once the streams are opened and does **not** emit a `connected` event.
- An explicit `disconnect` (`closeSession`) closes the session and does **not** emit a `disconnected` event.
- A session that dies on its own and the accessory-level disconnect notification are deduplicated by connection ID (via `reportedDisconnected`), so `onConnectionStateChanged` fires at most once per connection episode.

Preserve these semantics when changing the session code.

## iOS: no RFCOMM or SDP (critical)

iOS exposes no RFCOMM socket API and no SDP query API, and `IOBluetooth` (which the macOS serial manager uses) is macOS-only. Do not add an iOS serial/RFCOMM implementation, and do not route `BluetoothTransport.spp` to the External Accessory channel: `ExternalAccessory.connect` throws `UnsupportedError` for `spp`.

MFi/iAP2 accessories do carry their data channel over RFCOMM, and `EASession` surfaces that stream, so iOS is not without a byte pipe — but Apple's stack selects the channel from the accessory's advertised protocol string. On iOS the identifier is therefore always a protocol string, and there is no way to pass a device address or a service UUID. Keep that distinction when describing iOS in the README.

## Callback payloads

Callbacks live on the `UniversalBluetoothCallbacks` registry that `UniversalBluetoothInterface` exposes as `callbacks`; `UniversalBluetooth` owns the registry, injects it into the active implementation, and surfaces it through the `UniversalBluetooth` setters. Platform implementations forward inbound events to `callbacks`, never to global state.

- Use positional arguments for three values or fewer, or for internal plumbing (for example `onData(String identifier, Uint8List data)`).
- Use a model object for four or more related values, or when a payload is expected to grow past three. `onConnectionStateChanged` delivers a `BluetoothConnectionEvent` for exactly this reason.

Converting a positional callback to a model object is a **breaking change**: only on a major release, and only in a PR whose explicit purpose is that change.

## Generated code

Never hand-edit generated files (`*.g.dart`, `*.g.kt`, `*.g.swift`, `*.g.h`, `*.g.cpp`); the three definitions live in `pigeon/`. See [CONTRIBUTING.md](CONTRIBUTING.md#pigeon-and-generated-code) for the regeneration commands and the input-to-output mapping.

## Documentation

Keep `README.md` (including the platform support matrix) and `CHANGELOG.md` current with any API change. Every new or changed public API belongs in the platform matrix.
