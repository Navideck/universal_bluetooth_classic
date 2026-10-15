import FlutterMacOS
import Foundation
import IOBluetooth

/// Generic serial (SPP/RFCOMM) transport.
///
/// Opens an `IOBluetoothRFCOMMChannel` to a remote device for a service UUID
/// and forwards the byte stream to Flutter. This is a host/client-role
/// transport: it is unrelated to the HID service registration in
/// `UniversalBluetoothPlugin`.
public class BluetoothSerialManager: NSObject, BluetoothSerialPlatformChannel {
    private let callbackChannel: BluetoothSerialCallbackChannel

    /// Pending connect requests, keyed by device address. The RFCOMM channel can
    /// only be opened once the SDP query for the service UUID has completed.
    private var pendingConnects: [String: PendingConnect] = [:]
    /// Open RFCOMM channels, keyed by device address.
    private var rfcommChannels: [String: IOBluetoothRFCOMMChannel] = [:]

    init(callbackChannel: BluetoothSerialCallbackChannel) {
        self.callbackChannel = callbackChannel
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger: FlutterBinaryMessenger = registrar.messenger
        let callbackChannel = BluetoothSerialCallbackChannel(binaryMessenger: messenger)
        let instance = BluetoothSerialManager(callbackChannel: callbackChannel)
        BluetoothSerialPlatformChannelSetup.setUp(binaryMessenger: messenger, api: instance)
    }

    func connect(
        deviceId: String,
        serviceUuid: String,
        completion: @escaping (Result<Void, any Error>) -> Void
    ) {
        if rfcommChannels[deviceId] != nil {
            onConnectionUpdate(deviceId: deviceId, connected: true)
            completion(.success(()))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            guard let device = IOBluetoothDevice(addressString: deviceId) else {
                DispatchQueue.main.async {
                    completion(.failure(PigeonError(code: "Failed", message: "Device not found", details: nil)))
                }
                return
            }

            if !device.isConnected() {
                let ioReturn = device.openConnection(
                    nil,
                    withPageTimeout: UInt16(round(2.0 * 1600)),
                    authenticationRequired: true
                )
                if ioReturn != kIOReturnSuccess {
                    let errorString = String(cString: mach_error_string(Int32(ioReturn)))
                    DispatchQueue.main.async {
                        completion(.failure(PigeonError(code: "Failed", message: errorString, details: nil)))
                    }
                    return
                }
            }

            DispatchQueue.main.async {
                self.pendingConnects[deviceId] = PendingConnect(
                    deviceId: deviceId,
                    serviceUuid: serviceUuid,
                    completion: completion
                )
                let status = device.performSDPQuery(self)
                if status != kIOReturnSuccess {
                    self.pendingConnects.removeValue(forKey: deviceId)
                    completion(.failure(PigeonError(
                        code: "SDPFailed",
                        message: "Failed to start SDP query",
                        details: nil
                    )))
                }
            }
        }
    }

    func disconnect(deviceId: String, completion: @escaping (Result<Void, any Error>) -> Void) {
        guard let channel = rfcommChannels.removeValue(forKey: deviceId) else {
            completion(.success(()))
            return
        }
        channel.close()
        onConnectionUpdate(deviceId: deviceId, connected: false)
        completion(.success(()))
    }

    func send(deviceId: String, data: FlutterStandardTypedData) throws {
        guard let channel = rfcommChannels[deviceId] else {
            throw PigeonError(code: "NotFound", message: "No serial connection for \(deviceId)", details: nil)
        }
        let bytes = [UInt8](data.data)
        try bytes.withUnsafeBytes { bufferPointer in
            guard let baseAddress = bufferPointer.baseAddress else {
                throw PigeonError(code: "Failed", message: "Buffer pointer is nil", details: nil)
            }
            let result = channel.writeSync(
                UnsafeMutableRawPointer(mutating: baseAddress),
                length: UInt16(bufferPointer.count)
            )
            if result != kIOReturnSuccess {
                throw PigeonError(code: "Failed", message: "Failed to write to RFCOMM channel", details: nil)
            }
        }
    }

    /// Opens the RFCOMM channel once the SDP query for the service has completed.
    private func openRFCOMMChannel(device: IOBluetoothDevice, pending: PendingConnect) {
        guard let uuid = Self.sdpUUID(from: pending.serviceUuid) else {
            pending.completion(.failure(PigeonError(
                code: "InvalidUUID",
                message: "Invalid service UUID \(pending.serviceUuid)",
                details: nil
            )))
            return
        }

        guard let record = device.getServiceRecord(for: uuid) else {
            pending.completion(.failure(PigeonError(
                code: "ServiceNotFound",
                message: "Service \(pending.serviceUuid) not found on \(pending.deviceId)",
                details: nil
            )))
            return
        }

        var channelId: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelId) == kIOReturnSuccess else {
            pending.completion(.failure(PigeonError(
                code: "SDPFailed",
                message: "Service \(pending.serviceUuid) has no RFCOMM channel",
                details: nil
            )))
            return
        }

        var channel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelSync(&channel, withChannelID: channelId, delegate: self)
        guard result == kIOReturnSuccess, let openedChannel = channel else {
            let errorString = String(cString: mach_error_string(Int32(result)))
            pending.completion(.failure(PigeonError(
                code: "Failed",
                message: "Failed to open RFCOMM channel \(errorString)",
                details: nil
            )))
            return
        }

        rfcommChannels[pending.deviceId] = openedChannel
        onConnectionUpdate(deviceId: pending.deviceId, connected: true)
        pending.completion(.success(()))
    }

    private func onConnectionUpdate(deviceId: String, connected: Bool) {
        callbackChannel.onConnectionStateChanged(
            deviceId: deviceId,
            connected: connected,
            completion: { _ in }
        )
    }

    /// Builds an SDP UUID from a canonical UUID string. Common Bluetooth base
    /// UUIDs are collapsed to their 16-bit form so they match the service records
    /// that advertise the short UUID.
    private static func sdpUUID(from uuidString: String) -> IOBluetoothSDPUUID? {
        let hex = uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        guard hex.count == 32 else { return nil }

        let baseUUID = "00001000800000805F9B34FB"
        if hex.hasPrefix("0000") && hex.hasSuffix(baseUUID) {
            let start = hex.index(hex.startIndex, offsetBy: 4)
            let end = hex.index(start, offsetBy: 4)
            if let uuid16 = UInt16(hex[start..<end], radix: 16) {
                return IOBluetoothSDPUUID(uuid16: uuid16)
            }
        }

        var bytes = [UInt8]()
        var index = hex.startIndex
        for _ in 0..<16 {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return IOBluetoothSDPUUID(data: Data(bytes))
    }
}

/// A serial connect request waiting for the SDP query to finish.
private struct PendingConnect {
    let deviceId: String
    let serviceUuid: String
    let completion: (Result<Void, any Error>) -> Void
}

extension BluetoothSerialManager: IOBluetoothDeviceAsyncCallbacks {
    public func remoteNameRequestComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        print("Serial remoteNameRequestComplete \(String(describing: device.addressString)) \(status)")
    }

    public func connectionComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        print("Serial connectionComplete \(String(describing: device.addressString)) \(status)")
    }

    public func sdpQueryComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        guard let pending = pendingConnects.removeValue(forKey: device.addressString) else { return }
        guard status == kIOReturnSuccess else {
            pending.completion(.failure(PigeonError(
                code: "SDPFailed",
                message: "SDP query failed with status \(status)",
                details: nil
            )))
            return
        }
        openRFCOMMChannel(device: device, pending: pending)
    }
}

extension BluetoothSerialManager: IOBluetoothRFCOMMChannelDelegate {
    public func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel,
        data dataPointer: UnsafeMutableRawPointer,
        length dataLength: Int
    ) {
        guard dataLength > 0, let deviceId = rfcommChannel.getDevice()?.addressString else { return }
        let data = Data(bytes: dataPointer, count: dataLength)
        callbackChannel.onData(
            deviceId: deviceId,
            data: FlutterStandardTypedData(bytes: data),
            completion: { _ in }
        )
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        guard let deviceId = rfcommChannel.getDevice()?.addressString else { return }
        guard rfcommChannels.removeValue(forKey: deviceId) != nil else { return }
        onConnectionUpdate(deviceId: deviceId, connected: false)
    }
}
