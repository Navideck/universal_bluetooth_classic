import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_bluetooth_classic/src/platforms/accessory_manager.dart';
import 'package:universal_bluetooth_classic/src/generated/bluetooth_hid_manager.g.dart'
    as hid;
import 'package:universal_bluetooth_classic/universal_bluetooth_classic.dart';

/// Exercises the transport routing in [AccessoryManager] by intercepting the
/// Pigeon platform channels it sends on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMessageCodec();

  const hidBase =
      'dev.flutter.pigeon.universal_bluetooth_classic.BluetoothHidManagerPlatformChannel';
  const serialBase =
      'dev.flutter.pigeon.universal_bluetooth_classic.BluetoothSerialPlatformChannel';

  final channels = <String>[
    '$hidBase.connect',
    '$hidBase.send',
    '$hidBase.sendHidReport',
    '$hidBase.disconnect',
    '$serialBase.connect',
    '$serialBase.send',
    '$serialBase.disconnect',
  ];

  late List<String> calls;
  late TestDefaultBinaryMessenger messenger;

  setUpAll(() {
    // The router reads the platform once, when AccessoryManager is created.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  });

  tearDownAll(() {
    debugDefaultTargetPlatformOverride = null;
  });

  setUp(() {
    calls = <String>[];
    for (final name in channels) {
      messenger.setMockMessageHandler(name, (message) async {
        calls.add(name);
        return codec.encodeMessage(<Object?>[null]);
      });
    }
  });

  tearDown(() {
    for (final name in channels) {
      messenger.setMockMessageHandler(name, null);
    }
  });

  test('routes an spp connection, send, and disconnect to the serial channel',
      () async {
    final manager = AccessoryManager.instance;
    const id = '00:11:22:33:44:55';

    await manager.connect(id, transport: BluetoothTransport.spp);
    await manager.send(id, Uint8List.fromList([1, 2, 3]));
    await manager.disconnect(id);

    expect(calls, <String>[
      '$serialBase.connect',
      '$serialBase.send',
      '$serialBase.disconnect',
    ]);
  });

  test('routes a HID report with its report id to the HID channel', () async {
    final manager = AccessoryManager.instance;
    const id = 'AA:BB:CC:DD:EE:FF';

    await manager.connect(id);
    await manager.sendHidReport(id, 3, Uint8List.fromList([0xE9, 0x00]));

    expect(calls, <String>[
      '$hidBase.connect',
      '$hidBase.sendHidReport',
    ]);
  },
      skip:
          kIsWeb ? 'Native HID Pigeon codec requires Int64 accessors.' : false);

  test('sends identified reports on a peer-initiated HID connection', () async {
    final manager = AccessoryManager.instance;
    const id = '10:20:30:40:50:60';
    final delivered = Completer<void>();
    messenger.handlePlatformMessage(
      'dev.flutter.pigeon.universal_bluetooth_classic.BluetoothHidManagerCallbackChannel.onConnectionStateChanged',
      codec.encodeMessage(<Object?>[id, true]),
      (_) => delivered.complete(),
    );
    await delivered.future;
    await manager.sendHidReport(id, 128, Uint8List.fromList([1]));
    expect(calls, <String>['$hidBase.sendHidReport']);
    await manager.disconnect(id);
  },
      skip:
          kIsWeb ? 'Native HID Pigeon codec requires Int64 accessors.' : false);

  test('delivers report requests as a model and returns the reply', () async {
    final manager = AccessoryManager.instance;
    HidReportRequest? request;
    manager.callbacks.onReportRequest = (value) {
      request = value;
      return ReportReply(data: Uint8List.fromList([42]));
    };
    addTearDown(() => manager.callbacks.onReportRequest = null);
    const requestCodec =
        hid.BluetoothHidManagerCallbackChannel.pigeonChannelCodec;
    final response = Completer<ByteData?>();
    messenger.handlePlatformMessage(
      'dev.flutter.pigeon.universal_bluetooth_classic.BluetoothHidManagerCallbackChannel.onReportRequest',
      requestCodec.encodeMessage(<Object?>['peer', ReportType.input, 128, 64]),
      response.complete,
    );
    final reply = requestCodec.decodeMessage(await response.future) as List;
    expect(request!.deviceId, 'peer');
    expect(request!.type, ReportType.input);
    expect(request!.reportId, 128);
    expect(request!.bufferSize, 64);
    expect((reply.single as ReportReply).data, <int>[42]);

    manager.callbacks.onReportRequest = null;
    final declined = Completer<ByteData?>();
    messenger.handlePlatformMessage(
      'dev.flutter.pigeon.universal_bluetooth_classic.BluetoothHidManagerCallbackChannel.onReportRequest',
      requestCodec.encodeMessage(<Object?>['peer', ReportType.input, 128, 64]),
      declined.complete,
    );
    expect(requestCodec.decodeMessage(await declined.future), <Object?>[null]);
  },
      skip:
          kIsWeb ? 'Native HID Pigeon codec requires Int64 accessors.' : false);

  test('routes the default connection, send, and disconnect to the HID channel',
      () async {
    final manager = AccessoryManager.instance;
    const id = 'AA:BB:CC:DD:EE:FF';

    await manager.connect(id);
    await manager.send(id, Uint8List.fromList([1, 2, 3]));
    await manager.disconnect(id);

    expect(calls, <String>[
      '$hidBase.connect',
      '$hidBase.send',
      '$hidBase.disconnect',
    ]);
  });

  test('forgets the transport when a connect fails', () async {
    final manager = AccessoryManager.instance;
    const id = '11:22:33:44:55:66';

    // Make the serial connect fail. The router must drop the recorded transport
    // so the later send/disconnect fall back to HID rather than the serial
    // channel that never connected.
    messenger.setMockMessageHandler('$serialBase.connect', (message) async {
      calls.add('$serialBase.connect');
      return codec.encodeMessage(<Object?>['Failed', 'nope', null]);
    });

    await expectLater(
      manager.connect(id, transport: BluetoothTransport.spp),
      throwsA(isA<PlatformException>()),
    );
    await manager.send(id, Uint8List.fromList([1]));
    await manager.disconnect(id);

    expect(calls, <String>[
      '$serialBase.connect',
      '$hidBase.send',
      '$hidBase.disconnect',
    ]);
  });

  test('rejects a second connect while the first is in flight', () async {
    final manager = AccessoryManager.instance;
    const id = '22:33:44:55:66:77';
    final gate = Completer<ByteData?>();

    messenger.setMockMessageHandler('$serialBase.connect', (message) {
      calls.add('$serialBase.connect');
      return gate.future;
    });

    final first = manager.connect(id, transport: BluetoothTransport.spp);
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      manager.connect(id, transport: BluetoothTransport.spp),
      throwsA(isA<StateError>()),
    );

    // The rejected duplicate did not clear the transport the first connect
    // recorded, so the later disconnect still goes to the serial channel.
    gate.complete(codec.encodeMessage(<Object?>[null]));
    await first;
    await manager.disconnect(id);

    expect(calls, <String>[
      '$serialBase.connect',
      '$serialBase.disconnect',
    ]);
  });

  test('waits for a pending connect before disconnecting', () async {
    final manager = AccessoryManager.instance;
    const id = '33:44:55:66:77:88';
    final gate = Completer<ByteData?>();

    messenger.setMockMessageHandler('$serialBase.connect', (message) {
      calls.add('$serialBase.connect');
      return gate.future;
    });

    final connecting = manager.connect(id, transport: BluetoothTransport.spp);
    await Future<void>.delayed(Duration.zero);

    final disconnecting = manager.disconnect(id);
    await Future<void>.delayed(Duration.zero);

    // The disconnect has not reached the channel yet: it is waiting for the
    // connect to settle so the close lands on the socket the connect opens.
    expect(calls, <String>['$serialBase.connect']);

    gate.complete(codec.encodeMessage(<Object?>[null]));
    await connecting;
    await disconnecting;

    expect(calls, <String>[
      '$serialBase.connect',
      '$serialBase.disconnect',
    ]);
  });

  test('closeSdp fails clearly where SDP registration is unsupported', () {
    final manager = AccessoryManager.instance;
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(
      () => debugDefaultTargetPlatformOverride = TargetPlatform.android,
    );

    expect(() => manager.closeSdp(), throwsA(isA<UnsupportedError>()));
  });
}
