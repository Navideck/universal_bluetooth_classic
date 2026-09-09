// ignore_for_file: avoid_print

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:universal_bluetooth/universal_bluetooth.dart';
import 'package:universal_bluetooth_example/bluetooth_device.dart';
import 'package:universal_bluetooth_example/global_widgets.dart';
import 'package:universal_bluetooth_example/permission_handler.dart';

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  List<BluetoothDevice> devices = [];
  bool isScanning = false;
  bool showDevicesWithoutName = false;

  @override
  void initState() {
    UniversalBluetooth.accessoryConnected = (EAAccessory accessory) {
      print("Accessory Connected ${accessory.name}");
    };

    UniversalBluetooth.accessoryDisconnected = (EAAccessory accessory) {
      print("Accessory Disconnected ${accessory.name}");
    };

    UniversalBluetooth.onBluetoothDeviceDiscover = (device) {
      onBluetoothDeviceDiscover(device);
    };

    UniversalBluetooth.onBluetoothDeviceRemoved = (device) {
      print("Device Removed ${device.name} ${device.address}");
      devices.removeWhere((e) => e.address == device.address);
      setState(() {});
    };

    UniversalBluetooth.onConnectionStateChanged =
        (String deviceId, bool connected) {
      print("Connection State Changed $deviceId $connected");
      showSnackbar("$deviceId : ${connected ? 'Connected' : 'Disconnected'}");
    };

    UniversalBluetooth.onGetReport = (String deviceId, reportType, reportId) {
      print("Get Report $deviceId $reportType $reportId");

      if (reportType != ReportType.input) {
        return null; // Reply with error
      }

      return ReportReply(
        data: null, // Reply with data
      );
    };

    UniversalBluetooth.onSdpServiceRegistrationUpdate = (bool registered) {
      print("SDP Service Registered $registered");
      showSnackbar("SDP Service Registered $registered");
    };

    super.initState();
  }

  void onBluetoothDeviceDiscover(device) {
    if (!showDevicesWithoutName && (device.name == null || device.name == "")) {
      return;
    }
    print("Device Discover ${device.name} ${device.address}");
    int index = devices.indexWhere((e) => e.address == device.address);
    if (index == -1) {
      devices.add(device);
    } else {
      devices[index] = device;
    }
    setState(() {});
  }

  void showSnackbar(message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message.toString())),
    );
  }

  Future<void> startScan() async {
    setState(() {
      devices.clear();
      isScanning = true;
    });
    try {
      await UniversalBluetooth.startScan();
    } catch (e) {
      print(e);

      setState(() {
        isScanning = false;
      });
    }
  }

  Future<void> stopScan() async {
    setState(() {
      isScanning = false;
    });
    try {
      await UniversalBluetooth.stopScan();
    } catch (e) {
      print(e);
      setState(() {
        isScanning = true;
      });
    }
  }

  Future<void> getPairedDevices() async {
    try {
      var devices = await UniversalBluetooth.getPairedDevices();
      print(devices.map((e) => "${e.address} ${e.name}"));
    } catch (e) {
      print(e);
    }
  }

  Future<void> setupSdp() async {
    try {
      await UniversalBluetooth.setupSdp(
        config: SdpConfig(
          macSdpConfig: MacSdpConfig(
            sdpPlistFile: "SerialPortDictionary",
          ),
          androidSdpConfig: AndroidSdpConfig(
            name: "BlueHID",
            description: "Android HID",
            provider: "Android",
            subclass: 0x00,
            descriptors: Uint8List.fromList(androidDescriptor),
          ),
        ),
      );
    } catch (e) {
      print(e);
      showSnackbar(e);
    }
  }

  Future<void> closeSdp() async {
    try {
      await UniversalBluetooth.closeSdp();
    } catch (e) {
      print(e);
      showSnackbar(e);
    }
  }

  final List<int> androidDescriptor = [
    0x05, 0x01, // USAGE_PAGE (Generic Desktop)
    0x09, 0x06, // USAGE (Keyboard)
    0xa1, 0x01, // COLLECTION (Application)
    0x85, 0x01, //   REPORT_ID (1) - Assigning Report ID 1 to Keyboard
    0x05, 0x07, //   USAGE_PAGE (Keyboard)
    0x19, 0xe0, //   USAGE_MINIMUM (Keyboard LeftControl)
    0x29, 0xe7, //   USAGE_MAXIMUM (Keyboard Right GUI)
    0x15, 0x00, //   LOGICAL_MINIMUM (0)
    0x25, 0x01, //   LOGICAL_MAXIMUM (1)
    0x75, 0x01, //   REPORT_SIZE (1)
    0x95, 0x08, //   REPORT_COUNT (8)
    0x81, 0x02, //   INPUT (Data,Var,Abs)
    0x95, 0x01, //   REPORT_COUNT (1)
    0x75, 0x08, //   REPORT_SIZE (8)
    0x81, 0x03, //   INPUT (Cnst,Var,Abs)
    0x95, 0x05, //   REPORT_COUNT (5)
    0x75, 0x01, //   REPORT_SIZE (1)
    0x05, 0x08, //   USAGE_PAGE (LEDs)
    0x19, 0x01, //   USAGE_MINIMUM (Num Lock)
    0x29, 0x05, //   USAGE_MAXIMUM (Kana)
    0x91, 0x02, //   OUTPUT (Data,Var,Abs)
    0x95, 0x01, //   REPORT_COUNT (1)
    0x75, 0x03, //   REPORT_SIZE (3)
    0x91, 0x03, //   OUTPUT (Cnst,Var,Abs)
    0x95, 0x06, //   REPORT_COUNT (6)
    0x75, 0x08, //   REPORT_SIZE (8)
    0x15, 0x00, //   LOGICAL_MINIMUM (0)
    0x25, 0x65, //   LOGICAL_MAXIMUM (101)
    0x05, 0x07, //   USAGE_PAGE (Keyboard)
    0x19, 0x00, //   USAGE_MINIMUM (Reserved (no event indicated))
    0x29, 0x65, //   USAGE_MAXIMUM (Keyboard Application)
    0x81, 0x00, //   INPUT (Data,Ary,Abs)
    0xc0, // END_COLLECTION
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UniversalBluetooth'),
        actions: [
          if (isScanning)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: CircularProgressIndicator.adaptive(),
            ),
        ],
      ),
      body: Column(
        children: [
          ResponsiveButtonsGrid(
            children: [
              PlatformButton(
                onPressed: setupSdp,
                text: "SetupSdp",
              ),
              PlatformButton(
                onPressed: closeSdp,
                text: "CloseSdp",
              ),
              PlatformButton(
                onPressed: () async {
                  try {
                    print("Opening Picker");
                    await UniversalBluetooth.showBluetoothAccessoryPicker();
                    print("showed BluetoothAccessoryPicker");
                  } catch (e) {
                    print(e);
                  }
                },
                text: "ShowBluetoothAccessoryPicker",
              ),
              PlatformButton(
                onPressed: () async {
                  print("Closing EASession");
                  await UniversalBluetooth.closeEASession();
                  print("Closed EASession");
                },
                text: "Close EASession",
              ),
              PlatformButton(
                text: "Check Permissions",
                onPressed: () async {
                  bool hasPermissions =
                      await PermissionHandler.arePermissionsGranted();
                  if (hasPermissions) {
                    showSnackbar("Permissions granted");
                  }
                },
              ),
              PlatformButton(
                onPressed: startScan,
                text: "Start Scan",
              ),
              PlatformButton(
                onPressed: stopScan,
                text: "Stop Scan",
              ),
              PlatformButton(
                onPressed: () async {
                  try {
                    bool scanning = await UniversalBluetooth.isScanning();
                    print("Scanning: $scanning");
                  } catch (e) {
                    print(e);
                  }
                },
                text: "IsScanning",
              ),
              PlatformButton(
                onPressed: () async {
                  try {
                    devices.clear();
                    devices.addAll(
                      await UniversalBluetooth.getPairedDevices(),
                    );
                    print(devices.map((e) => "${e.address} ${e.name}"));
                    setState(() {});
                  } catch (e) {
                    print(e);
                  }
                },
                text: "Get Paired",
              ),
              PlatformButton(
                onPressed: () {
                  setState(() {
                    devices.clear();
                  });
                },
                text: "Clear List",
              ),
            ],
          ),
          SwitchListTile.adaptive(
              title: const Text("Show devices without name"),
              value: showDevicesWithoutName,
              onChanged: (value) {
                setState(() {
                  showDevicesWithoutName = !showDevicesWithoutName;
                });
              }),
          const Divider(),
          Expanded(
            child: ListView.separated(
              itemCount: devices.length,
              itemBuilder: (BuildContext context, int index) {
                BluetoothDevice device = devices[index];
                return BluetoothDeviceItem(device);
              },
              separatorBuilder: (BuildContext context, int index) {
                return const Divider();
              },
            ),
          )
        ],
      ),
    );
  }
}
