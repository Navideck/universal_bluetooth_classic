# Bluetooth Accessory Manager

<div align="center">
  <img src="assets/bluetooth_accessory_manager_banner.jpg" alt="Bluetooth Accessory Manager — Bluetooth Classic and External Accessory for Flutter" width="100%">
</div>

[![bluetooth_accessory_manager version](https://img.shields.io/pub/v/bluetooth_accessory_manager?label=bluetooth_accessory_manager)](https://pub.dev/packages/bluetooth_accessory_manager)

A cross-platform (Android/iOS/macOS/Windows/Linux) plugin for managing Bluetooth accessories and HID devices in Flutter.

## Features

- [Scanning](#scanning)
- [Pairing & Unpairing](#pairing--unpairing)
- [Connecting](#connecting)
- [HID Reports](#hid-reports)
- [SDP Service Registration](#sdp-service-registration)
- [iOS External Accessory](#ios-external-accessory)

## API Support

|                      | Android | iOS | macOS | Windows | Linux | Web |
| :------------------- | :-----: | :-: | :---: | :-----: | :---: | :-: |
| showBluetoothAccessoryPicker |   ✔️    | ✔️  |  ✔️   |   ✔️    | ❌  | ❌  |
| startScan/stopScan   |   ✔️    | ❌  |  ✔️   |   ✔️    | ✔️  | ❌  |
| pair/unpair          |   ✔️    | ❌  |  ✔️   |   ✔️    | ✔️  | ❌  |
| getPairedDevices     |   ✔️    | ❌  |  ✔️   |   ✔️    | ✔️  | ❌  |
| connect (HID)        |   ✔️    | ❌  |  ✔️   |   ✔️    | ❌  | ❌  |
| disconnect           |   ✔️    | ❌  |  ✔️   |   ✔️    | ✔️* | ❌  |
| sendReport           |   ✔️    | ❌  |  ✔️   |   ✔️    | ❌  | ❌  |
| setupSdp/closeSdp    |   ✔️    | ❌  |  ✔️   |   ✔️    | ❌  | ❌  |
| closeEASession       |   ❌    | ✔️  |  ❌   |   ❌    | ❌  | ❌  |
| accessoryConnected/Disconnected |   ❌    | ✔️  |  ❌   |   ❌    | ❌  | ❌  |
| onConnectionStateChanged (HID) |   ✔️    | ❌  |  ✔️   |   ✔️    | ❌  | ❌  |
| onGetReport          |   ✔️    | ❌  |  ✔️   |   ✔️    | ❌  | ❌  |
| onSdpServiceRegistrationUpdate |   ✔️    | ❌  |  ✔️   |   ✔️    | ❌  | ❌  |

*Linux `disconnect()` is basic disconnect only, not HID-specific.

## Getting Started

Add bluetooth_accessory_manager in your pubspec.yaml:

```yaml
dependencies:
  bluetooth_accessory_manager:
```

and import it wherever you want to use it:

```dart
import 'package:bluetooth_accessory_manager/bluetooth_accessory_manager.dart';
```

## Scanning

### Start Scanning

Start scanning for Bluetooth devices:

```dart
await BluetoothAccessoryManager.startScan();
```

### Stop Scanning

Stop scanning for Bluetooth devices:

```dart
await BluetoothAccessoryManager.stopScan();
```

### Check Scanning Status

Check if currently scanning:

```dart
bool isScanning = await BluetoothAccessoryManager.isScanning();
```

### Device Discovery

Listen to discovered devices:

```dart
BluetoothAccessoryManager.onBluetoothDeviceDiscover = (BluetoothDevice device) {
  print('Device discovered: ${device.name} (${device.address})');
  print('RSSI: ${device.rssi}');
  print('Paired: ${device.paired}');
  print('Device Type: ${device.deviceType}');
  print('Device Class: ${device.deviceClass}');
};
```

### Device Removed

Listen to device removal events:

```dart
BluetoothAccessoryManager.onBluetoothDeviceRemoved = (BluetoothDevice device) {
  print('Device removed: ${device.name} (${device.address})');
};
```

### Get Paired Devices

Get a list of all paired devices:

```dart
List<BluetoothDevice> devices = await BluetoothAccessoryManager.getPairedDevices();

for (var device in devices) {
  print('Paired device: ${device.name} - ${device.address}');
}
```

### Show Bluetooth Accessory Picker

Show the native Bluetooth accessory picker dialog. On iOS, this displays the External Accessory picker.

```dart
await BluetoothAccessoryManager.showBluetoothAccessoryPicker();
```

Optionally filter by device names:

```dart
await BluetoothAccessoryManager.showBluetoothAccessoryPicker(
  withNames: ['MyDevice', 'AnotherDevice'],
);
```

> **Note:** Not available on Linux.

## Pairing & Unpairing

### Pair

Pair with a Bluetooth device by its address:

```dart
bool success = await BluetoothAccessoryManager.pair('00:11:22:33:44:55');

if (success) {
  print('Device paired successfully');
} else {
  print('Pairing failed');
}
```

### Unpair

Unpair a Bluetooth device:

```dart
await BluetoothAccessoryManager.unpair('00:11:22:33:44:55');
```

## Connecting

### Connect (HID)

Connect to a Bluetooth HID device:

```dart
await BluetoothAccessoryManager.connect('00:11:22:33:44:55');
```

> **Platform Note:** Available on Android, macOS, and Windows. Not available on iOS (uses External Accessory framework) or Linux.

### Disconnect

Disconnect from a Bluetooth device:

```dart
await BluetoothAccessoryManager.disconnect('00:11:22:33:44:55');
```

### Connection State Changes

Listen to connection state changes:

```dart
BluetoothAccessoryManager.onConnectionStateChanged = (String deviceId, bool connected) {
  print('Device $deviceId: ${connected ? "connected" : "disconnected"}');
};
```

> **Platform Note:** Available on Android, macOS, and Windows (HID connections only). Not available on iOS or Linux.

## HID Reports

### Send Report

Send a HID report to a connected device:

```dart
import 'dart:typed_data';

Uint8List reportData = Uint8List.fromList([0x01, 0x02, 0x03]);
await BluetoothAccessoryManager.sendReport('00:11:22:33:44:55', reportData);
```

> **Platform Note:** Available on Android, macOS, and Windows. Not available on iOS or Linux.

### Get Report

Handle HID get report requests:

```dart
import 'dart:typed_data';

BluetoothAccessoryManager.onGetReport = (String deviceId, ReportType type, int bufferSize) {
  print('Get report request from $deviceId, type: $type, size: $bufferSize');
  
  // Return a report reply
  return ReportReply(
    data: Uint8List.fromList([0x01, 0x02, 0x03]),
    error: null,
  );
};
```

> **Platform Note:** Available on Android, macOS, and Windows. Not available on iOS or Linux.

## SDP Service Registration

### Setup SDP

Set up the SDP service registration for Bluetooth HID:

```dart
import 'dart:typed_data';

SdpConfig config = SdpConfig(
  macSdpConfig: MacSdpConfig(
    data: {
      'ServiceName': 'My HID Service',
      // ... other SDP data
    },
  ),
  androidSdpConfig: AndroidSdpConfig(
    name: 'My HID Service',
    description: 'HID Service Description',
    provider: 'My Company',
    subclass: 0x2540,
    descriptors: Uint8List.fromList([/* HID descriptors */]),
  ),
);

await BluetoothAccessoryManager.setupSdp(config: config);
```

### Close SDP

Close the SDP service registration:

```dart
await BluetoothAccessoryManager.closeSdp();
```

### SDP Registration Updates

Listen to SDP service registration status changes:

```dart
BluetoothAccessoryManager.onSdpServiceRegistrationUpdate = (bool registered) {
  print('SDP service ${registered ? "registered" : "unregistered"}');
};
```

> **Platform Note:** Available on Android, macOS, and Windows. Not available on iOS or Linux.

## iOS External Accessory

> **⚠️ iOS Only:** The following APIs are only available on iOS. On other platforms, they will throw `UnimplementedError`.

### Close EA Session

Close an External Accessory session. If no protocol string is provided, it will use the first available protocol:

```dart
await BluetoothAccessoryManager.closeEASession('com.mycompany.myprotocol');
```

### Accessory Connected

Listen to iOS External Accessory connection events:

```dart
BluetoothAccessoryManager.accessoryConnected = (EAAccessory accessory) {
  print('Accessory connected: ${accessory.name}');
  print('Manufacturer: ${accessory.manufacturer}');
  print('Model: ${accessory.modelNumber}');
  print('Protocols: ${accessory.protocolStrings}');
};
```

### Accessory Disconnected

Listen to iOS External Accessory disconnection events:

```dart
BluetoothAccessoryManager.accessoryDisconnected = (EAAccessory accessory) {
  print('Accessory disconnected: ${accessory.name}');
};
```

## Data Types

### BluetoothDevice

Represents a Bluetooth device:

```dart
BluetoothDevice device = ...;

print('Address: ${device.address}');
print('Name: ${device.name}');
print('Paired: ${device.paired}');
print('Connected with HID: ${device.isConnectedWithHid}');
print('RSSI: ${device.rssi}');
print('Device Type: ${device.deviceType}'); // classic, le, dual, unknown
print('Device Class: ${device.deviceClass}'); // peripheral, audioVideo, etc.
```

### EAAccessory (iOS)

Represents an iOS External Accessory:

```dart
EAAccessory accessory = ...;

print('Name: ${accessory.name}');
print('Manufacturer: ${accessory.manufacturer}');
print('Model: ${accessory.modelNumber}');
print('Serial: ${accessory.serialNumber}');
print('Firmware: ${accessory.firmwareRevision}');
print('Hardware: ${accessory.hardwareRevision}');
print('Dock Type: ${accessory.dockType}');
print('Protocols: ${accessory.protocolStrings}');
print('Connected: ${accessory.isConnected}');
print('Connection ID: ${accessory.connectionID}');
```

### SdpConfig

Configuration for SDP service registration:

```dart
SdpConfig config = SdpConfig(
  macSdpConfig: MacSdpConfig(
    sdpPlistFile: 'path/to/plist', // optional
    data: {
      'ServiceName': 'My Service',
      // ... other SDP data
    },
  ),
  androidSdpConfig: AndroidSdpConfig(
    name: 'My HID Service',
    description: 'Service Description',
    provider: 'My Company',
    subclass: 0x2540,
    descriptors: Uint8List.fromList([/* HID descriptors */]),
  ),
);
```

### ReportReply

Reply to a HID get report request:

```dart
ReportReply reply = ReportReply(
  data: Uint8List.fromList([0x01, 0x02, 0x03]),
  error: null, // null if successful, error code otherwise
);
```

### Enums

#### DeviceType

```dart
enum DeviceType {
  classic,  // Classic Bluetooth
  le,       // Bluetooth Low Energy
  dual,     // Dual mode (Classic + LE)
  unknown,  // Unknown type
}
```

#### DeviceClass

```dart
enum DeviceClass {
  audioVideo,
  computer,
  health,
  imaging,
  misc,
  networking,
  peripheral,
  phone,
  toy,
  uncategorized,
  wearable,
}
```

#### ReportType

```dart
enum ReportType {
  input,    // Input report
  output,   // Output report
  feature,  // Feature report
}
```

## Platform-Specific Setup

### Android

Add the following permissions to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" android:maxSdkVersion="28" />
```

Set minimum SDK to 23 in your `build.gradle`:

```gradle
android {
    defaultConfig {
        minSdkVersion 23
    }
}
```

You need to programmatically request permissions on runtime. You could use a package such as [permission_handler](https://pub.dev/packages/permission_handler).

For Android 12+, request `Permission.bluetoothScan` and `Permission.bluetoothConnect`.

For Android 11 and below, request `Permission.location`.

### iOS / macOS

Add Bluetooth accessory protocols to your `Info.plist`:

```xml
<key>UISupportedExternalAccessoryProtocols</key>
<array>
    <string>com.yourcompany.yourapp.protocol</string>
</array>
```

For macOS, add the `Bluetooth` capability to your app from Xcode.

### Windows / Linux

Your Bluetooth adapter needs to support at least Bluetooth 4.0. If you have more than 1 adapter, the first one returned from the system will be picked.

When publishing on Windows, you need to declare the following [capabilities](https://learn.microsoft.com/en-us/windows/uwp/packaging/app-capability-declarations): `bluetooth, radios`.

When publishing on Linux as a snap, you need to declare the `bluez` plug in `snapcraft.yaml`:

```yaml
...
  plugs:
    - bluez
```

## Platform-Specific APIs

### iOS-Only APIs

The following APIs are **only available on iOS**:

- `closeEASession([String? protocolString])` - Closes an External Accessory session
- `accessoryConnected` callback - Triggered when an iOS External Accessory is connected
- `accessoryDisconnected` callback - Triggered when an iOS External Accessory is disconnected

These APIs use the `EAAccessory` type which is iOS-specific. They will only be triggered on iOS when External Accessories are connected or disconnected.

### HID APIs (Not Available on iOS or Linux)

The following HID-related APIs are **not available on iOS** (which uses External Accessory framework instead) and **not available on Linux**:

- `connect(String deviceId)` - Connect to HID device
- `sendReport(String deviceId, Uint8List data)` - Send HID report
- `setupSdp({required SdpConfig config})` - Setup SDP service
- `closeSdp()` - Close SDP service
- `onGetReport` callback - Handle HID get report requests
- `onSdpServiceRegistrationUpdate` callback - SDP registration updates
- `onConnectionStateChanged` callback - HID connection state changes

**Available on:** Android, macOS, Windows

**Not available on:** iOS, Linux

**Note:** Linux does have `disconnect()` but not the other HID methods.

### Linux Limitations

On Linux, the following APIs are **not implemented**:

- `showBluetoothAccessoryPicker()` - Native picker not available
- `connect()` - HID connection not supported
- `sendReport()` - HID reports not supported
- `setupSdp()` - SDP service not supported
- `closeSdp()` - SDP service not supported

**Available on Linux:**
- `startScan()`, `stopScan()`, `isScanning()`
- `pair()`, `unpair()`
- `getPairedDevices()`
- `disconnect()` (basic disconnect only)
- `onBluetoothDeviceDiscover`, `onBluetoothDeviceRemoved` callbacks

## Customizing Platform Implementation

```dart
// Create a class that extends BluetoothAccessoryManagerInterface
class BluetoothAccessoryManagerMock extends BluetoothAccessoryManagerInterface {
  // Implement all methods
}

// Set custom platform specific implementation (e.g. for testing)
BluetoothAccessoryManager.setInstance(BluetoothAccessoryManagerMock());
```

## 🧩 Apps using Bluetooth Accessory Manager

Here are some of the apps leveraging the power of `bluetooth_accessory_manager` in production:

| <img src="assets/bt_cam_icon.svg" alt="BT Cam Icon" width="224" height="224"> | [**BT Cam**](https://btcam.app)<br>A Bluetooth remote app for DSLR and mirrorless cameras. Compatible with Canon, Nikon, Sony, Fujifilm, GoPro, Olympus, Panasonic, Pentax, and Blackmagic. Built using Bluetooth Accessory Manager to connect and control cameras across iOS, Android, macOS, Windows, Linux & Web. |
|:--:|:--|
> 💡 **Built something cool with Bluetooth Accessory Manager?**
> We'd love to showcase your app here!  
> Open a pull request and add it to this section. Please include your app icon in svg!
