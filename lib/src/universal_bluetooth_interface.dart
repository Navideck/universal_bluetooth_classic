import 'dart:typed_data';

import 'package:universal_bluetooth_classic/src/generated/bluetooth_hid_manager.g.dart';
import 'package:universal_bluetooth_classic/src/generated/external_accessory.g.dart';
import 'package:universal_bluetooth_classic/src/generated/universal_bluetooth.g.dart';
import 'package:universal_bluetooth_classic/src/sdp_config.dart';

/// Platform interface for [UniversalBluetooth].
///
/// Extend this class to provide a custom or mocked platform implementation.
/// Unsupported operations throw [UnimplementedError] by default.
abstract class UniversalBluetoothInterface {
  /// The registry the implementation reports inbound events to.
  ///
  /// [UniversalBluetooth] assigns its own registry when it selects the active
  /// implementation. A platform implementation must forward its inbound events
  /// to these fields; app code registers them through the
  /// `UniversalBluetooth.onXxx` setters rather than touching this directly.
  UniversalBluetoothCallbacks callbacks = UniversalBluetoothCallbacks();

  /// Opens the platform Bluetooth accessory picker, optionally filtered by
  /// [withNames].
  Future<void> showBluetoothAccessoryPicker({List<String>? withNames}) {
    throw UnimplementedError();
  }

  /// Connects to the device with the given [deviceId].
  ///
  /// [transport] selects the Bluetooth Classic transport:
  ///
  /// * Omitted or `null` (the default) picks the platform's natural data
  ///   transport: Bluetooth HID on Android and macOS, serial (SPP/RFCOMM) on
  ///   Windows, and an External Accessory session on iOS.
  /// * [BluetoothTransport.hid] connects over Bluetooth HID.
  /// * [BluetoothTransport.spp] opens a serial (SPP/RFCOMM) connection. When
  ///   [serviceUuid] is omitted, the well-known [sppServiceUuid] is used.
  /// * [BluetoothTransport.externalAccessory] opens an External Accessory
  ///   session. It is iOS-only.
  ///
  /// [serviceUuid] is only meaningful for [BluetoothTransport.spp]; it lets a
  /// serial accessory advertise a custom service UUID instead of the SPP one.
  Future<void> connect(
    String deviceId, {
    BluetoothTransport? transport,
    String? serviceUuid,
    Duration? timeout,
  }) {
    throw UnimplementedError();
  }

  /// Disconnects a device, or closes iOS External Accessory sessions.
  ///
  /// On iOS, [identifier] is an optional protocol string; when omitted, every
  /// open session is closed.
  Future<void> disconnect([String? identifier]) {
    throw UnimplementedError();
  }

  /// Registers a Bluetooth HID service using the given [config].
  Future<void> setupSdp(SdpConfig config) {
    throw UnimplementedError();
  }

  /// Closes the registered Bluetooth HID service.
  Future<void> closeSdp() {
    throw UnimplementedError();
  }

  /// Sends raw [data] to the connected device with the given [deviceId].
  ///
  /// On iOS the device is identified by its External Accessory protocol string
  /// and the session must have been opened with [connect]. On the HID platforms
  /// this sends an output report. For a serial
  /// ([BluetoothTransport.spp]) connection the bytes are written to the RFCOMM
  /// channel.
  Future<void> send(String deviceId, Uint8List data) {
    throw UnimplementedError();
  }

  /// Sends an input report with an explicit HID report id.
  ///
  /// [reportId] is separate from [data], matching the HID transports that carry
  /// the id out-of-band. Prefer this over [send] for descriptors that declare
  /// report ids.
  Future<void> sendHidReport(String deviceId, int reportId, Uint8List data) {
    throw UnimplementedError();
  }

  /// Starts scanning for nearby Bluetooth devices.
  Future<void> startScan() {
    throw UnimplementedError();
  }

  /// Stops the ongoing Bluetooth scan.
  Future<void> stopScan() {
    throw UnimplementedError();
  }

  /// Whether a Bluetooth scan is currently running.
  Future<bool> isScanning() {
    throw UnimplementedError();
  }

  /// Pairs the Bluetooth device with the given [address]. Returns whether the
  /// pairing succeeded.
  Future<bool> pair(String address) {
    throw UnimplementedError();
  }

  /// Unpairs the Bluetooth device with the given [address].
  Future<void> unpair(String address) {
    throw UnimplementedError();
  }

  /// Returns the list of already paired Bluetooth devices.
  Future<List<BluetoothDevice>> getPairedDevices() {
    throw UnimplementedError();
  }
}

/// Callback for device discovery and removal events.
typedef BluetoothDeviceCallback = void Function(BluetoothDevice device);

/// Callback for connection state changes.
typedef ConnectionChangeCallback = void Function(
  BluetoothConnectionEvent event,
);

/// The connection state of a Bluetooth device.
enum BluetoothConnectionState { connected, disconnected }

/// The source that triggered a connection state change.
enum BluetoothConnectionSource { hid, externalAccessory, spp, system }

/// The Bluetooth Classic transport used to reach a device.
///
/// Not every transport is available on every platform; see the README support
/// matrix for the per-platform details. There is no default member: passing
/// `null` (or omitting the `transport` argument of `connect`) selects the
/// platform's natural transport instead.
enum BluetoothTransport {
  /// Bluetooth HID. Available on Android and macOS.
  hid,

  /// Serial Port Profile (SPP) over RFCOMM. Available on Android, macOS, and
  /// Windows.
  spp,

  /// An Apple External Accessory session. Available on iOS only.
  externalAccessory,
}

/// The well-known Serial Port Profile (SPP) service UUID.
const String sppServiceUuid = '00001101-0000-1000-8000-00805F9B34FB';

/// Describes a connection state change of a Bluetooth device.
class BluetoothConnectionEvent {
  /// Creates a connection state change event.
  const BluetoothConnectionEvent({
    required this.identifier,
    required this.state,
    required this.source,
    this.externalAccessory,
  });

  /// Identifier of the affected device.
  final String identifier;

  /// The new connection state.
  final BluetoothConnectionState state;

  /// The source that triggered the change.
  final BluetoothConnectionSource source;

  /// The iOS External Accessory value, when [source] is
  /// [BluetoothConnectionSource.externalAccessory].
  final EAAccessory? externalAccessory;
}

/// Callback for HID get-report requests.
typedef GetReportCallback = ReportReply? Function(
  String deviceId,
  ReportType type,
  int bufferSize,
);

/// A HID report requested by the connected peer.
class HidReportRequest {
  /// Creates a request received from the native HID transport.
  const HidReportRequest({
    required this.deviceId,
    required this.type,
    required this.reportId,
    required this.bufferSize,
  });

  /// The requesting device's address.
  final String deviceId;

  /// The requested report type.
  final ReportType type;

  /// The unsigned report ID from the descriptor, or zero if IDs are unused.
  final int reportId;

  /// The buffer size requested by the peer.
  final int bufferSize;
}

/// Callback for HID report requests that carry the report id.
///
/// Takes precedence over [GetReportCallback] when a non-null reply is returned.
typedef ReportRequestCallback = ReportReply? Function(HidReportRequest request);

/// Callback for data received from a connected device.
typedef DataCallback = void Function(String identifier, Uint8List data);

/// Callback for SDP service registration status changes.
typedef SdpServiceRegistrationUpdateCallback = void Function(bool registered);

/// The inbound events a [UniversalBluetoothInterface] implementation reports.
///
/// Every field is `null` until the app registers a callback through the
/// matching `UniversalBluetooth.onXxx` setter, so implementations must
/// null-check before invoking them.
class UniversalBluetoothCallbacks {
  /// Called when a Bluetooth device is discovered during a scan.
  BluetoothDeviceCallback? onDeviceDiscovered;

  /// Called when a previously discovered Bluetooth device is removed.
  BluetoothDeviceCallback? onDeviceRemoved;

  /// Called when the connection state of a device changes.
  ConnectionChangeCallback? onConnectionStateChanged;

  /// Called when the platform requests a HID report.
  GetReportCallback? onGetReport;

  /// Called when the platform requests a HID report, with its report id.
  ///
  /// A non-null reply takes precedence over [onGetReport].
  ReportRequestCallback? onReportRequest;

  /// Called when data is received from a connected device.
  DataCallback? onData;

  /// Called when the SDP service registration status changes.
  SdpServiceRegistrationUpdateCallback? onSdpServiceRegistrationUpdate;
}
