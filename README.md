# Universal Bluetooth

<div align="center">
  <img src="assets/universal_bluetooth_banner.png" alt="Universal Bluetooth — Bluetooth Classic and External Accessory for Flutter" width="100%">
</div>

[![pub package](https://img.shields.io/pub/v/universal_bluetooth_classic?label=universal_bluetooth_classic&color=blue)](https://pub.dev/packages/universal_bluetooth_classic)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-lightgrey)](https://github.com/Navideck/universal_bluetooth)
[![GitHub stars](https://img.shields.io/github/stars/Navideck/universal_bluetooth?style=social)](https://github.com/Navideck/universal_bluetooth)
[![pub points](https://img.shields.io/pub/points/universal_bluetooth_classic?color=2E7D32)](https://pub.dev/packages/universal_bluetooth_classic/score)
[![Flutter](https://img.shields.io/badge/Flutter-%3E%3D3.3.0-blue.svg?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%3E%3D3.1.3-blue.svg?logo=dart)](https://dart.dev)

A cross-platform Flutter plugin for discovering, pairing, and managing Bluetooth Classic accessories, Bluetooth HID devices, and Apple External Accessory sessions.

> Looking for Bluetooth Low Energy and GATT? See [universal_ble](https://pub.dev/packages/universal_ble).

## Features

- [**Device discovery**](#scanning) — scan for nearby Bluetooth devices and retrieve paired devices.
- [**Pairing**](#pairing) — pair and unpair accessories by address.
- [**Native accessory picker**](#native-accessory-picker) — open the platform picker, with optional device-name filtering.
- [**Bluetooth HID**](#connecting) — connect to HID devices and exchange reports.
- [**SDP registration**](#sdp-service-registration) — advertise a Bluetooth HID service.
- [**Apple External Accessory**](#ios-external-accessory) — receive connection events and manage EA sessions on iOS.
- [**Five desktop and mobile platforms**](#api-support) — Android, iOS, macOS, Windows, and Linux.

## API Support

| API | Android | iOS | macOS | Windows | Linux |
| :-- | :--: | :--: | :--: | :--: | :--: |
| `showBluetoothAccessoryPicker` | ✔️ | ✔️ | ✔️ | ✔️ | — |
| `startScan` / `stopScan` | ✔️ | — | ✔️ | ✔️ | ✔️ |
| `pair` / `unpair` | ✔️ | — | ✔️ | ✔️ | ✔️ |
| `getPairedDevices` | ✔️ | — | ✔️ | ✔️ | ✔️ |
| `connect` (HID) | ✔️ | — | ✔️ | ✔️ | — |
| `disconnect` | ✔️ | ✔️² | ✔️ | ✔️ | ✔️¹ |
| `sendReport` | ✔️ | — | ✔️ | ✔️ | — |
| `setupSdp` / `closeSdp` | ✔️ | — | ✔️ | ✔️ | — |
| `onConnectionStateChanged` | ✔️ | ✔️ | ✔️ | — | ✔️ |
| `onGetReport` | ✔️ | — | ✔️ | ✔️ | — |
| `onSdpServiceRegistrationUpdate` | ✔️ | — | ✔️ | ✔️ | — |

¹ Linux supports a basic disconnect, not an HID-specific disconnect.
² On iOS, `disconnect` closes an External Accessory session.

## Getting Started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  universal_bluetooth_classic: ^0.2.0
```

Import it where you need it:

```dart
import 'package:universal_bluetooth_classic/universal_bluetooth_classic.dart';
```

Complete the setup for each target in [Platform-specific setup](#platform-specific-setup) before using the APIs below.

## Scanning

Register discovery callbacks before starting a scan:

```dart
UniversalBluetooth.onDeviceDiscovered = (device) {
  print('${device.name ?? 'Unknown'} (${device.address}), RSSI ${device.rssi}');
};

UniversalBluetooth.onDeviceRemoved = (device) {
  print('Removed: ${device.address}');
};

await UniversalBluetooth.startScan();
```

Check or stop the scan when needed:

```dart
final isScanning = await UniversalBluetooth.isScanning();

if (isScanning) {
  await UniversalBluetooth.stopScan();
}
```

Scanning is available on Android, macOS, Windows, and Linux.

### Paired devices

```dart
final devices = await UniversalBluetooth.getPairedDevices();

for (final device in devices) {
  print('${device.name ?? 'Unknown'} — ${device.address}');
}
```

### Native accessory picker

Open the platform's Bluetooth accessory picker. On iOS, this uses the External Accessory picker.

```dart
await UniversalBluetooth.showBluetoothAccessoryPicker();
```

Optionally filter by device name:

```dart
await UniversalBluetooth.showBluetoothAccessoryPicker(
  withNames: ['MyDevice', 'AnotherDevice'],
);
```

The native picker is not available on Linux.

## Pairing

Pair or unpair a device by its Bluetooth address:

```dart
final paired = await UniversalBluetooth.pair(
  '00:11:22:33:44:55',
);

if (paired) {
  print('Device paired');
}

await UniversalBluetooth.unpair('00:11:22:33:44:55');
```

Pairing APIs are available on Android, macOS, Windows, and Linux.

## Connecting

Connect to and disconnect from a Bluetooth HID device:

```dart
const deviceId = '00:11:22:33:44:55';

UniversalBluetooth.onConnectionStateChanged = (event) {
  print('${event.identifier}: ${event.state.name} (${event.source.name})');
};

await UniversalBluetooth.connect(deviceId);
await UniversalBluetooth.disconnect(deviceId);
```

HID connections are available on Android, macOS, and Windows. iOS uses the External Accessory framework instead. Linux supports only the basic `disconnect` operation.

## HID Reports

Send a report to a connected HID device:

```dart
import 'dart:typed_data';

await UniversalBluetooth.sendReport(
  '00:11:22:33:44:55',
  Uint8List.fromList([0x01, 0x02, 0x03]),
);
```

Respond to HID get-report requests:

```dart
UniversalBluetooth.onGetReport =
    (deviceId, reportType, bufferSize) {
  return ReportReply(
    data: Uint8List.fromList([0x01, 0x02, 0x03]),
  );
};
```

HID reports are available on Android, macOS, and Windows.

## SDP Service Registration

Register a Bluetooth HID service with platform-specific configuration:

```dart
import 'dart:typed_data';

final config = SdpConfig(
  macSdpConfig: MacSdpConfig(
    data: {
      'ServiceName': 'My HID Service',
      // Add the remaining SDP properties.
    },
  ),
  androidSdpConfig: AndroidSdpConfig(
    name: 'My HID Service',
    description: 'HID Service Description',
    provider: 'My Company',
    subclass: 0x2540,
    descriptors: Uint8List.fromList([
      // Add the HID report descriptor.
    ]),
  ),
);

UniversalBluetooth.onSdpServiceRegistrationUpdate = (registered) {
  print('SDP service registered: $registered');
};

await UniversalBluetooth.setupSdp(config: config);
```

Close the registration when it is no longer needed:

```dart
await UniversalBluetooth.closeSdp();
```

SDP registration is available on Android, macOS, and Windows.

## iOS External Accessory

External Accessory sessions are iOS-only, but their connection changes use the
same callback as the other platforms.

```dart
UniversalBluetooth.onConnectionStateChanged = (event) {
  final accessory = event.externalAccessory;
  if (accessory == null) return;

  print('${event.state.name}: ${accessory.name}');
  print('Manufacturer: ${accessory.manufacturer}');
  print('Protocols: ${accessory.protocolStrings}');
};
```

Close a session for a specific protocol:

```dart
await UniversalBluetooth.disconnect(
  'com.mycompany.myprotocol',
);
```

Omit the protocol string to close the session using the first available protocol:

```dart
await UniversalBluetooth.disconnect();
```

The `externalAccessory` event payload is only available on iOS.

## Data Types

### `BluetoothDevice`

Discovered and paired devices expose:

- `address`
- `name`
- `paired`
- `isConnectedWithHid`
- `rssi`
- `deviceType` — `classic`, `le`, `dual`, or `unknown`
- `deviceClass` — for example `peripheral`, `audioVideo`, or `computer`

### `EAAccessory`

iOS External Accessory events provide the accessory name, manufacturer, model and serial numbers, firmware and hardware revisions, dock type, supported protocol strings, connection status, and connection ID.

### `BluetoothConnectionEvent`

Connection events provide an opaque identifier, a `connected` or `disconnected`
state, and a source: `hid`, `externalAccessory`, or `system`. The External
Accessory source also includes the full iOS `EAAccessory` value.

### HID configuration

- `SdpConfig` holds the platform-specific `MacSdpConfig` and `AndroidSdpConfig` values used for service registration.
- `ReportReply` returns optional report `data` or an optional HID `error` code from `onGetReport`.
- `ReportType` identifies `input`, `output`, and `feature` reports.

## Platform-specific setup

### Android

Add the Bluetooth permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="28" />
```

Set the minimum Android SDK to 23:

```gradle
android {
    defaultConfig {
        minSdkVersion 23
    }
}
```

Request permissions at runtime. For Android 12 and newer, request Bluetooth scan and connect permissions. For Android 11 and older, request location permission. Packages such as [permission_handler](https://pub.dev/packages/permission_handler) can handle these requests.

### iOS

Declare every External Accessory protocol supported by your accessory in `ios/Runner/Info.plist`:

```xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
    <string>com.yourcompany.yourapp.protocol</string>
</array>
```

### macOS

Add the Bluetooth capability to your macOS target in Xcode.

### Windows

The Bluetooth adapter must support Bluetooth 4.0 or newer. If the system has multiple adapters, the plugin uses the first adapter returned by Windows.

When packaging the app, declare the [`bluetooth` and `radios` capabilities](https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations).

### Linux

The Bluetooth adapter must support Bluetooth 4.0 or newer. If the system has multiple adapters, the plugin uses the first adapter returned by BlueZ.

When distributing the app as a snap, add the `bluez` plug to `snapcraft.yaml`:

```yaml
plugs:
  - bluez
```

Linux supports scanning, paired-device lookup, pairing, unpairing, basic disconnects, discovery callbacks, and system connection-state events. The native picker, HID connections and reports, and SDP registration are not implemented.

## Customizing Platform Implementation

Provide a custom implementation for testing or an unsupported platform by extending `UniversalBluetoothInterface`:

```dart
class UniversalBluetoothMock
    extends UniversalBluetoothInterface {
  // Override the APIs used by your application.
}

UniversalBluetooth.setInstance(
  UniversalBluetoothMock(),
);
```

Restore the default platform implementation with:

```dart
UniversalBluetooth.setInstance(null);
```

## Example app

The [`example`](example) project demonstrates discovery, pairing, HID connections, reports, SDP registration, and platform permission handling.

Run it on a connected device or desktop target:

```sh
cd example
flutter run
```

## App showcase

| | |
| :--: | :-- |
| <img src="assets/bt_cam_icon.svg" alt="BT Cam icon" width="160" height="160"> | [**BT Cam**](https://btcam.app)<br>A Bluetooth remote for Canon, Nikon, Sony, Fujifilm, GoPro, Olympus, Panasonic, Pentax, and Blackmagic cameras. |

> Built something with Universal Bluetooth? Open a pull request to add it here, including an SVG app icon.
