import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:universal_bluetooth_classic/universal_bluetooth_classic.dart';
import 'package:universal_bluetooth_example/global_widgets.dart';

class BluetoothDeviceItem extends StatelessWidget {
  final BluetoothDevice device;
  const BluetoothDeviceItem(this.device, {super.key});

  Future<void> pairDevice() async {
    try {
      print("Pairing");
      bool paired = await UniversalBluetooth.pair(device.address);
      print("Pair: $paired");
    } catch (e) {
      print(e);
    }
  }

  Future<void> unPairDevice() async {
    try {
      print("Unpairing ${device.address}");
      await UniversalBluetooth.unpair(device.address);
      print("Unpaired");
    } catch (e) {
      print(e);
    }
  }

  Future<void> disconnect() async {
    print("Disconnecting");
    await UniversalBluetooth.disconnect(device.address);
    print("Disconnected");
  }

  Future<void> connect() async {
    try {
      print("Connecting");
      await UniversalBluetooth.connect(device.address);
      print("Connected Successfully");
    } catch (e) {
      print("ConnectionFailed $e");
    }
  }

  Future<void> sendReport() async {
    try {
      if (Platform.isAndroid) {
        await sendAndroidKeyboardKey();
      } else if (Platform.isMacOS) {
        await sendMacKeyboardKey();
      }
    } catch (e) {
      print(e);
    }
  }

  Future<void> sendAndroidKeyboardKey() async {
    await UniversalBluetooth.sendReport(
      device.address,
      Uint8List.fromList(
        [0x01, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00],
      ), // Key A Down
    );
    await Future.delayed(const Duration(milliseconds: 200));
    await UniversalBluetooth.sendReport(
      device.address,
      Uint8List.fromList(
        [0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00],
      ), // Key A Up
    );
  }

  Future<void> sendMacKeyboardKey() async {
    await UniversalBluetooth.sendReport(
      device.address,
      Uint8List.fromList(macHidReport(0x04, 0)), //  Key A Down
    );
    await Future.delayed(const Duration(milliseconds: 200));
    await UniversalBluetooth.sendReport(
      device.address,
      Uint8List.fromList(macHidReport(0, 0)), // Key A Up
    );
  }

  List<int> macHidReport(int keyCode, int modifier) {
    return [
      0xA1, // 0 DATA | INPUT (HIDP Bluetooth)
      0x01, // 0 Report ID
      modifier, // 1 Modifier Keys
      0x00, // 2 Reserved
      keyCode, // 3 Keys ( 6 keys can be held at the same time )
      0x00, // 4
      0x00, // 5
      0x00, // 6
      0x00, // 7
      0x00, // 8
      0x00, // 9
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          title: Text(device.name ?? "N/A"),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(device.address),
              if (device.deviceClass != null)
                Text(device.deviceClass!.toString()),
              if (device.deviceType != null)
                Text(device.deviceType!.toString()),
              Text("Paired: ${device.paired}"),
              Text("ConnectedWithHID: ${device.isConnectedWithHid}"),
            ],
          ),
          trailing: Text(device.rssi.toString()),
        ),
        ResponsiveButtonsGrid(
          children: [
            PlatformButton(
              onPressed: pairDevice,
              text: "Pair",
            ),
            PlatformButton(
              onPressed: unPairDevice,
              text: "UnPair",
            ),
            PlatformButton(
              onPressed: connect,
              text: "Connect",
            ),
            PlatformButton(
              onPressed: disconnect,
              text: "Disconnect",
            ),
            PlatformButton(
              onPressed: sendReport,
              text: "Send Report",
            ),
          ],
        )
      ],
    );
  }
}
