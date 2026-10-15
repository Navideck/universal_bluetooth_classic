import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_bluetooth_classic/src/transport_router.dart';
import 'package:universal_bluetooth_classic/universal_bluetooth_classic.dart';

void main() {
  group('TransportRouter.resolveConnect', () {
    test('auto resolves to HID on Android and macOS', () {
      expect(
        TransportRouter(
          platform: TargetPlatform.android,
        ).resolveConnect(BluetoothTransport.auto),
        BluetoothTransport.hid,
      );
      expect(
        TransportRouter(
          platform: TargetPlatform.macOS,
        ).resolveConnect(BluetoothTransport.auto),
        BluetoothTransport.hid,
      );
    });

    test('auto resolves to serial on Windows (no HID implementation)', () {
      expect(
        TransportRouter(
          platform: TargetPlatform.windows,
        ).resolveConnect(BluetoothTransport.auto),
        BluetoothTransport.spp,
      );
    });

    test('explicit transports are returned unchanged on every platform', () {
      for (final platform in TargetPlatform.values) {
        final router = TransportRouter(platform: platform);
        expect(
          router.resolveConnect(BluetoothTransport.hid),
          BluetoothTransport.hid,
        );
        expect(
          router.resolveConnect(BluetoothTransport.spp),
          BluetoothTransport.spp,
        );
      }
    });
  });

  group('TransportRouter active transport', () {
    test('records, returns, and forgets the transport for a device', () {
      final router = TransportRouter(platform: TargetPlatform.android);

      expect(router.transportFor('00:11:22:33:44:55'), isNull);

      router.record('00:11:22:33:44:55', BluetoothTransport.spp);
      expect(
        router.transportFor('00:11:22:33:44:55'),
        BluetoothTransport.spp,
      );

      router.record('00:11:22:33:44:55', BluetoothTransport.hid);
      expect(
        router.transportFor('00:11:22:33:44:55'),
        BluetoothTransport.hid,
      );

      router.forget('00:11:22:33:44:55');
      expect(router.transportFor('00:11:22:33:44:55'), isNull);
    });
  });
}
