import 'package:pigeon/pigeon.dart';

// dart run pigeon --input pigeon/bluetooth_hid_manager.dart
// Generates File for Android, Mac
@ConfigurePigeon(
  PigeonOptions(
    dartPackageName: 'universal_bluetooth_classic',
    dartOut: 'lib/src/generated/bluetooth_hid_manager.g.dart',
    dartOptions: DartOptions(),
    kotlinOut:
        'android/src/main/kotlin/com/navideck/universal_bluetooth_classic/BluetoothHidManager.g.kt',
    swiftOut:
        'macos/universal_bluetooth_classic/Sources/universal_bluetooth_classic/BluetoothHidManager.g.swift',
    swiftOptions: SwiftOptions(includeErrorClass: false),
    kotlinOptions: KotlinOptions(
      package: 'com.navideck.universal_bluetooth_classic',
      includeErrorClass: false,
    ),
    // cppOptions: CppOptions(namespace: 'universal_bluetooth_classic'),
    // cppHeaderOut: 'windows/BluetoothHidManager.g.h',
    // cppSourceOut: 'windows/BluetoothHidManager.g.cpp',
    debugGenerators: true,
  ),
)

/// Flutter -> Native
@HostApi()
abstract class BluetoothHidManagerPlatformChannel {
  void closeSdp();

  @asyncCallback
  void connect(String deviceId, int? timeoutMillis);

  @asyncCallback
  void disconnect(String deviceId);

  void send(String deviceId, Uint8List data);

  /// Sends an input report with an explicit HID report id.
  ///
  /// [reportId] is passed separately from [data], matching Android's
  /// `BluetoothHidDevice.sendReport` and the macOS report channel. Prefer this
  /// over [send] for descriptors that declare report ids: the id must not be
  /// embedded in the payload.
  void sendHidReport(String deviceId, int reportId, Uint8List data);
}

/// Native -> Flutter
@FlutterApi()
abstract class BluetoothHidManagerCallbackChannel {
  @asyncCallback
  void onConnectionStateChanged(String deviceId, bool connected);

  @asyncCallback
  void onSdpServiceRegistrationUpdate(bool registered);

  @asyncCallback
  ReportReply? onGetReport(String deviceId, ReportType type, int bufferSize);

  /// Additive report request carrying the requested report id.
  ///
  /// A non-null reply takes precedence over [onGetReport]. When neither
  /// callback answers, the native side reports an unsupported request.
  @asyncCallback
  ReportReply? onReportRequest(
    String deviceId,
    ReportType type,
    int reportId,
    int bufferSize,
  );

  @asyncCallback
  void onData(String deviceId, Uint8List data);
}

class ReportReply {
  int? error;
  Uint8List? data;
  ReportReply({this.error, this.data});
}

enum ReportType { input, output, feature }
