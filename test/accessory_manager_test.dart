import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_bluetooth_classic/src/platforms/accessory_manager.dart';
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
}
