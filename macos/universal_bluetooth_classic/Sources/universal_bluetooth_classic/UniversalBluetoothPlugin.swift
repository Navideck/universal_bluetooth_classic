import AppKit
import Carbon.HIToolbox
import Cocoa
import FlutterMacOS
import Foundation
import IOBluetooth
import IOKit.hid
#if SWIFT_PACKAGE
import BluetoothPairingController
#endif

public class UniversalBluetoothPlugin: NSObject, FlutterPlugin {
    var accessoryManagerCallbackChannel: FlutterAccessoryCallbackChannel
    var hidCallbackChannel: BluetoothHidManagerCallbackChannel

    var sdpService: IOBluetoothSDPServiceRecord?
    var controlNotification: IOBluetoothUserNotification?
    var interruptNotification: IOBluetoothUserNotification?

    var delegateMap: [String: BTDevice] = [:]
    private lazy var inquiryScanner = MacInquiryScanner()

    // We initialize IOBluetoothPairingController in ObjC because in Swift no modal is shown
    // This also does not work on native apps
    private lazy var pairingController = IOBluetoothPairingControllerObjC()

    init(callbackChannel: FlutterAccessoryCallbackChannel, hidCallback: BluetoothHidManagerCallbackChannel) {
        accessoryManagerCallbackChannel = callbackChannel
        hidCallbackChannel = hidCallback
        super.init()
        inquiryScanner.onDeviceFound = { [weak self] device in
            guard let self else { return }
            self.accessoryManagerCallbackChannel.onDeviceDiscover(
                device: device.toBLuetoothDevice(self.delegateMap)
            ) { _ in }
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger: FlutterBinaryMessenger = registrar.messenger
        let callbackChannel = FlutterAccessoryCallbackChannel(binaryMessenger: messenger)
        let hidCallback = BluetoothHidManagerCallbackChannel(binaryMessenger: messenger)
        let instance = UniversalBluetoothPlugin(callbackChannel: callbackChannel, hidCallback: hidCallback)
        FlutterAccessoryPlatformChannelSetup.setUp(binaryMessenger: messenger, api: instance)
        BluetoothHidManagerPlatformChannelSetup.setUp(binaryMessenger: messenger, api: instance)
        MacSdpChannelSetup.setUp(binaryMessenger: messenger, api: instance)
        BluetoothSerialManager.register(with: registrar)
    }
}

extension UniversalBluetoothPlugin: MacSdpChannel {
    func setupSdp(config: MacSdpConfig) throws {
        try setupBluetoothSdpConfig(config: config)
    }
}

extension UniversalBluetoothPlugin: BluetoothHidManagerPlatformChannel {
    func closeSdp() throws {
        sdpService?.remove()
        controlNotification?.unregister()
        interruptNotification?.unregister()
        sdpService = nil
        controlNotification = nil
        interruptNotification = nil
        hidCallbackChannel.onSdpServiceRegistrationUpdate(registered: false) { _ in }
    }

    func connect(deviceId: String, timeoutMillis: Int64?, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let device = IOBluetoothDevice(addressString: deviceId) else {
            completion(.failure(PigeonError(code: "Failed", message: "Device not found", details: nil)))
            return
        }

        let existing = delegateMap[deviceId]
        if device.isConnected(), existing?.controlChannel != nil {
            setupL2CAPChannels(device: device, deviceId: deviceId, completion: completion)
            return
        }

        // Open the connection off the platform thread, since it can block while
        // the page timeout elapses.
        DispatchQueue.global(qos: .userInitiated).async {
            let ioReturn = device.openConnection(
                nil,
                withPageTimeout: UInt16(round(2.0 * 1600)),
                authenticationRequired: true
            )
            if ioReturn != kIOReturnSuccess {
                let errorString = String(cString: mach_error_string(Int32(ioReturn)))
                completion(.failure(PigeonError(code: "Failed", message: errorString, details: nil)))
                return
            }
            DispatchQueue.main.async {
                self.setupL2CAPChannels(device: device, deviceId: deviceId, completion: completion)
            }
        }
    }

    private func setupL2CAPChannels(
        device: IOBluetoothDevice,
        deviceId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let btDevice = delegateMap[deviceId] ?? BTDevice()

        if btDevice.interruptChannel != nil && btDevice.controlChannel != nil {
            print("Channel already opened")
            btDevice.reportedConnected = true
            onConnectionUpdate(deviceId: deviceId, connected: true)
            completion(.success(()))
            return
        }

        btDevice.device = device
        device.performSDPQuery(self)

        var controlChannel: IOBluetoothL2CAPChannel?
        var result = device.openL2CAPChannelSync(&controlChannel, withPSM: BTChannels.Control, delegate: self)
        if result != kIOReturnSuccess {
            let errorString = String(cString: mach_error_string(Int32(result)))
            completion(.failure(PigeonError(code: "Failed", message: "Failed to open ControlChannel \(result) \(errorString)", details: nil)))
            return
        }
        btDevice.controlChannel = controlChannel

        var interruptChannel: IOBluetoothL2CAPChannel?
        result = device.openL2CAPChannelSync(&interruptChannel, withPSM: BTChannels.Interrupt, delegate: self)
        if result != kIOReturnSuccess {
            // A half-open session must not look usable: close what we opened.
            controlChannel?.close()
            btDevice.controlChannel = nil
            btDevice.interruptChannel = nil
            btDevice.reportedConnected = false
            let errorString = String(cString: mach_error_string(Int32(result)))
            completion(.failure(PigeonError(code: "Failed", message: "Failed to open Interrupt \(result) \(errorString)", details: nil)))
            return
        }
        btDevice.interruptChannel = interruptChannel

        delegateMap[device.addressString] = btDevice
        // Only both channels together are a usable HID session.
        if btDevice.controlChannel != nil && btDevice.interruptChannel != nil {
            btDevice.reportedConnected = true
            onConnectionUpdate(deviceId: deviceId, connected: true)
            completion(.success(()))
        } else {
            completion(.failure(PigeonError(code: "Failed", message: "HID channels incomplete", details: nil)))
        }
    }


    func disconnect(deviceId: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let device = IOBluetoothDevice(addressString: deviceId) else {
            completion(.failure(PigeonError(code: "Failed", message: "Device not found", details: nil)))
            return
        }
        // Close connection
        let ioReturn: IOReturn = device.closeConnection()
        if ioReturn != kIOReturnSuccess {
            let errorString = String(cString: mach_error_string(Int32(ioReturn)))
            completion(.failure(PigeonError(code: "Failed", message: errorString, details: nil)))
            return
        }
        // Close channels
        if let btDevice = delegateMap[deviceId] {
            btDevice.interruptChannel?.close()
            btDevice.controlChannel?.close()
        }
        completion(.success(()))
    }

    func send(deviceId: String, data: FlutterStandardTypedData) throws {
        let byteArray = [UInt8](data.data)
        if let interruptChannel = delegateMap[deviceId]?.interruptChannel {
            try sendBytes(channel: interruptChannel, byteArray)
        } else {
            throw PigeonError(code: "Failed", message: "No interruptChannel", details: nil)
        }
    }

    func sendHidReport(deviceId: String, reportId: Int64, data: FlutterStandardTypedData) throws {
        // macOS writes raw HIDP packets to the interrupt channel. The first
        // octet is the DATA|INPUT transaction header, followed by the report id
        // when the descriptor declares one.
        var payload = [UInt8](data.data)
        if reportId > 0 {
            payload.insert(UInt8(reportId & 0xFF), at: 0)
        }
        payload.insert(0xA1, at: 0)
        if let interruptChannel = delegateMap[deviceId]?.interruptChannel {
            try sendBytes(channel: interruptChannel, payload)
        } else {
            throw PigeonError(code: "Failed", message: "No interruptChannel", details: nil)
        }
    }
}

extension UniversalBluetoothPlugin: FlutterAccessoryPlatformChannel {
    func startScan() throws {
        do {
            try inquiryScanner.start()
        } catch MacInquiryError.failedToStart(let code) {
            throw PigeonError(
                code: "Failed",
                message: "Failed to start inquiry: \(code)",
                details: nil
            )
        }
    }

    func stopScan() throws {
        inquiryScanner.stop()
    }

    func isScanning() throws -> Bool {
        inquiryScanner.isScanning
    }

    func getPairedDevices() throws -> [BluetoothDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() else { return [] }
        return paired.map { device -> [BluetoothDevice] in
            guard let d = device as? IOBluetoothDevice else { return [] }
            return [d.toBLuetoothDevice(delegateMap)]
        }.flatMap { $0 }
    }

    func showBluetoothAccessoryPicker(withNames _: [String], completion: @escaping (Result<Void, Error>) -> Void) {
        pairingController.performSelector(
            onMainThread: #selector(IOBluetoothPairingController.runModal),
            with: nil,
            waitUntilDone: false
        )
        completion(.success(()))
    }

    func pair(address: String, completion: @escaping (Result<Bool, Error>) -> Void) {
        MacPairer.pair(address: address) { result in
            switch result {
            case .success(let paired):
                completion(.success(paired))
            case .failure(let error):
                completion(.failure(PigeonError(
                    code: "Failed",
                    message: String(describing: error),
                    details: nil
                )))
            }
        }
    }

    func unpair(address: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let device = IOBluetoothDevice(addressString: address) else {
            completion(.failure(PigeonError(code: "DeviceNotFound", message: "Device not found", details: nil)))
            return
        }

        // There is no public API for unPairing, so we need this ugly hack with a custom selector
        let selector = Selector(("remove"))
        if device.responds(to: selector) {
            device.perform(selector)
        }

        if (device.isPaired()) {
            completion(.failure(PigeonError(code: "Failed", message: "Failed to unpair", details: nil)))
        } else {
            completion(.success(()))
        }
    }
}

extension UniversalBluetoothPlugin: IOBluetoothDeviceAsyncCallbacks {
    public func remoteNameRequestComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        print("RemoteNameRequestComplete \(String(describing: device.addressString)) \(status)")
    }

    public func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        print("ConnectionComplete \(String(describing: device.addressString)) \(status)")
    }

    public func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        if status == kIOReturnSuccess {
            print("SDP query completed successfully for device: \(device)")
        } else {
            print("SDP query failed with status: \(status)")
        }
    }
}

extension UniversalBluetoothPlugin: IOBluetoothL2CAPChannelDelegate {
    func setupBluetoothSdpConfig(config: MacSdpConfig) throws {
        if sdpService != nil {
            throw PigeonError(code: "AlreadyInitialized", message: "SDP service already initialized", details: nil)
        }

        let bluetoothHost = IOBluetoothHostController()
        bluetoothHost.setClassOfDevice(0x002540, forTimeInterval: 60)

        var sdpDict: NSDictionary? = nil

        if let sdpPlist = config.sdpPlistFile {
            guard let dictPath = Bundle.main.path(forResource: sdpPlist, ofType: "plist") else {
                 throw PigeonError(code: "FileNotFound", message: "SDP plist file '\(sdpPlist).plist' not found in bundle", details: nil)
             }
             guard let dict = NSDictionary(contentsOfFile: dictPath) else {
                 throw PigeonError(code: "InvalidPlist", message: "Failed to load NSDictionary from file at path: \(dictPath)", details: nil)
             }
             sdpDict = dict
        } else if let sdpPlistData = config.data {
            // TODO: Fix this
            sdpDict = NSDictionary(dictionary: sdpPlistData)
        }

        if sdpDict == nil {
            throw PigeonError(code: "Failed to setup SDP", message: "SDP Dictionary is nil", details: nil)
        }

        // Bluetooth SDP Service
        sdpService = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: sdpDict! as [NSObject: AnyObject])

        // Open Channels for Incoming Connections
        guard let controlChannel = IOBluetoothL2CAPChannel
            .register(forChannelOpenNotifications: self,
                      selector: #selector(newL2CAPChannelOpened),
                      withPSM: BTChannels.Control,
                      direction: kIOBluetoothUserNotificationChannelDirectionIncoming)
        else {
            sdpService = nil
            throw PigeonError(code: "Failed", message: "Failed to register ControlChannel", details: nil)
        }

        guard let interruptChannel = IOBluetoothL2CAPChannel
            .register(forChannelOpenNotifications: self,
                      selector: #selector(newL2CAPChannelOpened),
                      withPSM: BTChannels.Interrupt,
                      direction: kIOBluetoothUserNotificationChannelDirectionIncoming)
        else {
            sdpService = nil
            throw PigeonError(code: "Failed", message: "Failed to register InterruptChannel", details: nil)
        }

        controlNotification = controlChannel
        interruptNotification = interruptChannel

        // Send Sdp registered
        hidCallbackChannel.onSdpServiceRegistrationUpdate(registered: true) { _ in }
        // TODO: Check if we have Callback when Sdp Unregister
    }

    private func sendBytes(channel: IOBluetoothL2CAPChannel, _ bytes: [UInt8]) throws {
        try bytes.withUnsafeBytes { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else {
                throw PigeonError(code: "Failed", message: "Buffer pointer is nil", details: nil)
            }
            let ioError = channel.writeAsync(UnsafeMutableRawPointer(mutating: baseAddress),
                                             length: UInt16(bufferPointer.count),
                                             refcon: nil)
            if ioError != kIOReturnSuccess {
                throw PigeonError(code: "Failed", message: "Failed to send data \(channel.psm)", details: nil)
            }
        }
    }

    // Triggers when Interrupt Channel will be connected/disconnected from device
    private func onConnectionUpdate(deviceId: String, connected: Bool) {
        hidCallbackChannel.onConnectionStateChanged(deviceId: deviceId, connected: connected) { _ in }
    }

    @objc public func l2capChannelOpenComplete(_ channel: IOBluetoothL2CAPChannel, status: IOReturn) {
        if status != kIOReturnSuccess {
            print("L2capChannelOpenCompleteStatus \(status)")
        }
        guard let deviceId: String = channel.device?.addressString else {
            print("ChannelOpened but no device address")
            return
        }
        switch channel.psm {
        case BTChannels.Control:
            print("Opened ControlChannel for \(deviceId)")
            let btDevice = session(for: deviceId)
            btDevice.controlChannel = channel
        case BTChannels.Interrupt:
            print("Opened InterruptChannel for \(deviceId)")
            let btDevice = session(for: deviceId)
            btDevice.interruptChannel = channel
        default:
            return
        }
        reportConnectedIfReady(deviceId: deviceId)
    }

    @objc public func l2capChannelClosed(_ channel: IOBluetoothL2CAPChannel) {
        guard let deviceId: String = channel.device?.addressString else {
            print("ChannelClosed but no device address")
            return
        }
        let btDevice = delegateMap[deviceId]
        switch channel.psm {
        case BTChannels.Control:
            print("Closed ControlChannel for \(deviceId)")
            if btDevice?.controlChannel === channel {
                btDevice?.controlChannel = nil
            }
        case BTChannels.Interrupt:
            print("Closed InterruptChannel for \(deviceId)")
            if btDevice?.interruptChannel === channel {
                btDevice?.interruptChannel = nil
            }
        default:
            return
        }
        // Either channel closing invalidates the session, even if the other one
        // is still open. Report the loss once and drop ownership of the broken
        // session so a reconnect starts from a clean state.
        let wasConnected = btDevice?.reportedConnected == true
        if let btDevice {
            btDevice.reportedConnected = false
            if btDevice.controlChannel == nil || btDevice.interruptChannel == nil {
                btDevice.controlChannel?.close()
                btDevice.interruptChannel?.close()
                btDevice.controlChannel = nil
                btDevice.interruptChannel = nil
                delegateMap.removeValue(forKey: deviceId)
            }
        }
        if wasConnected {
            onConnectionUpdate(deviceId: deviceId, connected: false)
        }
    }

    @objc private func l2capChannelWriteComplete(channel _: IOBluetoothL2CAPChannel, refcon _: UnsafeMutableRawPointer, status _: IOReturn) {
        print("l2capChannelWriteComplete")
    }

    @objc func newL2CAPChannelOpened(notification _: IOBluetoothUserNotification, channel: IOBluetoothL2CAPChannel) {
        print("NewChannelOpened")
        channel.setDelegate(self)
        guard let deviceId = channel.device?.addressString else { return }
        let btDevice = session(for: deviceId)
        switch channel.psm {
        case BTChannels.Control:
            btDevice.controlChannel = channel
        case BTChannels.Interrupt:
            btDevice.interruptChannel = channel
        default:
            return
        }
        reportConnectedIfReady(deviceId: deviceId)
    }

    /// The established session for [deviceId], creating and owning it when the
    /// first channel arrives. Incoming channels can therefore create a session
    /// even when the app never initiated a connect.
    private func session(for deviceId: String) -> BTDevice {
        if let existing = delegateMap[deviceId] {
            return existing
        }
        let session = BTDevice()
        session.device = IOBluetoothDevice(addressString: deviceId)
        delegateMap[deviceId] = session
        return session
    }

    /// Emits a single connected event once both HID channels are open.
    private func reportConnectedIfReady(deviceId: String) {
        guard let btDevice = delegateMap[deviceId],
              btDevice.controlChannel != nil,
              btDevice.interruptChannel != nil else { return }
        if btDevice.reportedConnected { return }
        btDevice.reportedConnected = true
        onConnectionUpdate(deviceId: deviceId, connected: true)
    }

    @objc private func l2capChannelData(channel: IOBluetoothL2CAPChannel, data dataPointer: UnsafePointer<UInt8>, length dataLength: Int) {
        let data = UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>?(dataPointer), count: dataLength)
        if channel.psm == BTChannels.Interrupt {
            // Data arriving on the interrupt channel is forwarded as-is.
            guard dataLength > 0, let deviceId = channel.device?.addressString else { return }
            let payload = FlutterStandardTypedData(bytes: Data(buffer: data))
            hidCallbackChannel.onData(deviceId: deviceId, data: payload) { _ in }
            return
        }
        if channel.psm == BTChannels.Control {
            guard data.count > 0 else { return }
            guard let messageType = BTMessageType(rawValue: data[0] >> 4)
            else { return }
            switch messageType {
            case .Handshake:
                print("Got Handshake")
                return
            case .HIDControl:
                print("Got HidControl")
                channel.device.closeConnection()
            case .SetReport, .SetProtocol:
                print("Sending HandShake")
                do {
                    guard channel.psm == BTChannels.Control else {
                        print("Passing wrong channel to handshake")
                        return
                    }
                    try sendBytes(channel: channel, [0x0 | UInt8(0)])
                } catch {
                    print(error)
                }
            default:
                print("Unhandled \(messageType)")
                return
            }
        }
    }
}

extension IOBluetoothDevice {
    func toBLuetoothDevice(_ delegateMap: [String: BTDevice]) -> BluetoothDevice {
        return BluetoothDevice(
            address: addressString,
            name: name,
            paired: isPaired(),
            isConnectedWithHid: delegateMap[addressString]?.interruptChannel != nil,
            rssi: Int64(rssi()),
            deviceClass: deviceClassMajor.toDeviceClass(),
            deviceType: nil
        )
    }
}

enum BTMessageType: UInt8 {
    case Handshake = 0,
         HIDControl
    case GetReport = 4,
         SetReport,
         GetProtocol,
         SetProtocol
    case Data = 0xA
}

enum BTChannels {
    static let Control = BluetoothL2CAPPSM(kBluetoothL2CAPPSMHIDControl)
    static let Interrupt = BluetoothL2CAPPSM(kBluetoothL2CAPPSMHIDInterrupt)
}

class BTDevice {
    var device: IOBluetoothDevice?
    var interruptChannel: IOBluetoothL2CAPChannel?
    var controlChannel: IOBluetoothL2CAPChannel?
    var reportedConnected = false
}

extension BluetoothDeviceClassMajor {
    func toDeviceClass() -> DeviceClass? {
        switch Int(self) {
        case kBluetoothDeviceClassMajorComputer:
            return DeviceClass.computer
        case kBluetoothDeviceClassMajorPhone:
            return DeviceClass.phone
        case kBluetoothDeviceClassMajorLANAccessPoint:
            return DeviceClass.networking
        case kBluetoothDeviceClassMajorAudio:
            return DeviceClass.audioVideo
        case kBluetoothDeviceClassMajorPeripheral:
            return DeviceClass.peripheral
        case kBluetoothDeviceClassMajorWearable:
            return DeviceClass.wearable
        case kBluetoothDeviceClassMajorToy:
            return DeviceClass.toy
        case kBluetoothDeviceClassMajorHealth:
            return DeviceClass.health
        case kBluetoothDeviceClassMajorUnclassified:
            return DeviceClass.uncategorized
        case kBluetoothDeviceClassMajorMiscellaneous:
            return DeviceClass.misc
        case kBluetoothDeviceClassMajorImaging:
            return DeviceClass.imaging
        default:
            return nil
        }
    }
}
