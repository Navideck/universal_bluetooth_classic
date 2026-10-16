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
    lazy var inquiry: IOBluetoothDeviceInquiry = .init(delegate: self)
    private var isInquiryStarted = false

    // We initialize IOBluetoothPairingController in ObjC because in Swift no modal is shown
    // This also does not work on native apps
    private lazy var pairingController = IOBluetoothPairingControllerObjC()

    init(callbackChannel: FlutterAccessoryCallbackChannel, hidCallback: BluetoothHidManagerCallbackChannel) {
        accessoryManagerCallbackChannel = callbackChannel
        hidCallbackChannel = hidCallback
        super.init()
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
        Task {
            try? await hidCallbackChannel.onSdpServiceRegistrationUpdate(registered: false)
        }
    }

    func connect(deviceId: String) async throws {
        guard let device = IOBluetoothDevice(addressString: deviceId) else {
            throw PigeonError(code: "Failed", message: "Device not found", details: nil)
        }

        if !device.isConnected() {
            let ioReturn: IOReturn = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let device = IOBluetoothDevice(addressString: deviceId) else {
                        continuation.resume(returning: kIOReturnSuccess)
                        return
                    }
                    let result = device.openConnection(
                        nil,
                        withPageTimeout: UInt16(round(2.0 * 1600)),
                        authenticationRequired: true
                    )
                    continuation.resume(returning: result)
                }
            }

            if ioReturn != kIOReturnSuccess {
                let errorString = String(cString: mach_error_string(Int32(ioReturn)))
                throw PigeonError(code: "Failed", message: errorString, details: nil)
            }
        }

        try await setupL2CAPChannels(device: device, deviceId: deviceId)
    }
    
    
    @MainActor
    private func setupL2CAPChannels(device: IOBluetoothDevice, deviceId: String) throws {
        let btDevice = delegateMap[deviceId] ?? BTDevice()
        
        if btDevice.interruptChannel != nil && btDevice.controlChannel != nil {
            print("Channel already opened")
            onConnectionUpdate(deviceId: deviceId, connected: true)
            return
        }
        
        btDevice.device = device
        device.performSDPQuery(self)
        
        var result = device.openL2CAPChannelSync(&btDevice.controlChannel, withPSM: BTChannels.Control, delegate: self)
        if result != kIOReturnSuccess {
            let errorString = String(cString: mach_error_string(Int32(result)))
            throw PigeonError(code: "Failed", message: "Failed to open ControlChannel \(result) \(errorString)", details: nil)
        }

        result = device.openL2CAPChannelSync(&btDevice.interruptChannel, withPSM: BTChannels.Interrupt, delegate: self)
        if result != kIOReturnSuccess {
            let errorString = String(cString: mach_error_string(Int32(result)))
            throw PigeonError(code: "Failed", message: "Failed to open Interrupt \(result) \(errorString)", details: nil)
        }

        self.delegateMap[device.addressString] = btDevice
    }


    func disconnect(deviceId: String) async throws {
        guard let device = IOBluetoothDevice(addressString: deviceId) else {
            throw PigeonError(code: "Failed", message: "Device not found", details: nil)
        }
        // Close connection
        let ioReturn: IOReturn = device.closeConnection()
        if ioReturn != kIOReturnSuccess {
            let errorString = String(cString: mach_error_string(Int32(ioReturn)))
            throw PigeonError(code: "Failed", message: errorString, details: nil)
        }
        // Close channels
        if let btDevice = delegateMap[deviceId] {
            btDevice.interruptChannel?.close()
            btDevice.controlChannel?.close()
        }
    }

    func send(deviceId: String, data: FlutterStandardTypedData) throws {
        let byteArray = [UInt8](data.data)
        if let interruptChannel = delegateMap[deviceId]?.interruptChannel {
            try sendBytes(channel: interruptChannel, byteArray)
        } else {
            throw PigeonError(code: "Failed", message: "No interruptChannel", details: nil)
        }
    }
}

extension UniversalBluetoothPlugin: FlutterAccessoryPlatformChannel {
    func startScan() throws {
        inquiry.updateNewDeviceNames = true
        inquiry.inquiryLength = 3
        inquiry.start()
    }

    func stopScan() throws {
        inquiry.stop()
    }

    func isScanning() throws -> Bool {
        return isInquiryStarted
    }

    func getPairedDevices() throws -> [BluetoothDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() else { return [] }
        return paired.map { device -> [BluetoothDevice] in
            guard let d = device as? IOBluetoothDevice else { return [] }
            return [d.toBLuetoothDevice(delegateMap)]
        }.flatMap { $0 }
    }

    func showBluetoothAccessoryPicker(withNames _: [String]) async throws {
        await MainActor.run {
            pairingController.performSelector(
                onMainThread: #selector(IOBluetoothPairingController.runModal),
                with: nil,
                waitUntilDone: false
            )
        }
    }

    func pair(address: String) async throws -> Bool {
        // Open the connection off the platform thread, since it can block while
        // the page timeout elapses.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            DispatchQueue.global(qos: .background).async {
                guard let device = IOBluetoothDevice(addressString: address) else {
                    continuation.resume(throwing: PigeonError(code: "Failed", message: "Device not found", details: nil))
                    return
                }

                if device.isConnected() {
                    print("Already connected \(address)")
                    continuation.resume(returning: true)
                    return
                }

                let ioReturn: IOReturn = device.openConnection(
                    nil,
                    withPageTimeout: UInt16(round(2.0 * 1600)),
                    authenticationRequired: true
                )

                if ioReturn == kIOReturnSuccess {
                    continuation.resume(returning: true)
                    return
                }

                let errorString = String(cString: mach_error_string(Int32(ioReturn)))
                continuation.resume(throwing: PigeonError(code: "Failed", message: errorString, details: nil))
            }
        }
    }
    
    func unpair(address: String) async throws {
        guard let device = IOBluetoothDevice(addressString: address) else {
            throw PigeonError(code: "DeviceNotFound", message: "Device not found", details: nil)
        }
        
        // There is no public API for unPairing, so we need this ugly hack with a custom selector
        let selector = Selector(("remove"))
        if device.responds(to: selector) {
            device.perform(selector)
        }
        
        if (device.isPaired()) {
            throw PigeonError(code: "Failed", message: "Failed to unpair", details: nil)
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

extension UniversalBluetoothPlugin: IOBluetoothDeviceInquiryDelegate {
    @objc public func deviceInquiryStarted(_: IOBluetoothDeviceInquiry) {
        isInquiryStarted = true
    }

    @objc public func deviceInquiryComplete(_: IOBluetoothDeviceInquiry, error: IOReturn, aborted _: Bool) {
        isInquiryStarted = false
        if error != kIOReturnSuccess {
            print("Inquiry failed with error: \(error)")
        }
    }

    @objc public func deviceInquiryDeviceFound(_: IOBluetoothDeviceInquiry, device: IOBluetoothDevice) {
        Task {
            try? await accessoryManagerCallbackChannel.onDeviceDiscover(
                device: device.toBLuetoothDevice(delegateMap)
            )
        }
    }

    @objc public func deviceInquiryUpdatingDeviceNamesStarted(_: IOBluetoothDeviceInquiry, devicesRemaining: UInt32) {
        print("Updating device names started: devicesRemaining = \(devicesRemaining)")
    }

    @objc public func deviceInquiryDeviceNameUpdated(_: IOBluetoothDeviceInquiry, device: IOBluetoothDevice, devicesRemaining: UInt32) {
        print("Device name updated: devicesRemaining = \(devicesRemaining), name = \(String(describing: device.nameOrAddress))")
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
        Task {
            try? await hidCallbackChannel.onSdpServiceRegistrationUpdate(registered: true)
        }
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
        Task {
            try? await hidCallbackChannel.onConnectionStateChanged(deviceId: deviceId, connected: connected)
        }
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
            delegateMap[deviceId]?.controlChannel = channel
        case BTChannels.Interrupt:
            print("Opened InterruptChannel for \(deviceId)")
            delegateMap[deviceId]?.interruptChannel = channel
            onConnectionUpdate(deviceId: deviceId, connected: true)
        default:
            return
        }
    }

    @objc public func l2capChannelClosed(_ channel: IOBluetoothL2CAPChannel) {
        guard let deviceId: String = channel.device?.addressString else {
            print("ChannelClosed but no device address")
            return
        }
        switch channel.psm {
        case BTChannels.Control:
            print("Closed ControlChannel for \(deviceId)")
            delegateMap[deviceId]?.controlChannel = nil
        case BTChannels.Interrupt:
            print("Closed InterruptChannel for \(deviceId)")
            delegateMap[deviceId]?.interruptChannel = nil
            onConnectionUpdate(deviceId: deviceId, connected: false)
        default:
            return
        }
    }

    @objc private func l2capChannelWriteComplete(channel _: IOBluetoothL2CAPChannel, refcon _: UnsafeMutableRawPointer, status _: IOReturn) {
        print("l2capChannelWriteComplete")
    }

    @objc func newL2CAPChannelOpened(notification _: IOBluetoothUserNotification, channel: IOBluetoothL2CAPChannel) {
        print("NewChannelOpened")
        channel.setDelegate(self)
    }

    @objc private func l2capChannelData(channel: IOBluetoothL2CAPChannel, data dataPointer: UnsafePointer<UInt8>, length dataLength: Int) {
        let data = UnsafeBufferPointer<UInt8>(start: UnsafePointer<UInt8>?(dataPointer), count: dataLength)
        if channel.psm == BTChannels.Interrupt {
            // Data arriving on the interrupt channel is forwarded as-is.
            guard dataLength > 0, let deviceId = channel.device?.addressString else { return }
            let payload = FlutterStandardTypedData(bytes: Data(buffer: data))
            Task {
                try? await hidCallbackChannel.onData(deviceId: deviceId, data: payload)
            }
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
