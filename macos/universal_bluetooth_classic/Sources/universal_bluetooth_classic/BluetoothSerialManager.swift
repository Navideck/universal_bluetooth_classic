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

    func connect(deviceId: String, serviceUuid: String) async throws {
        if rfcommChannels[deviceId] != nil {
            onConnectionUpdate(deviceId: deviceId, connected: true)
            return
        }
        // A second connect while the SDP query is still running would overwrite
        // the pending continuation and leave the first caller waiting forever.
        if pendingConnects[deviceId] != nil {
            throw PigeonError(
                code: "InProgress",
                message: "A connection to \(deviceId) is already in progress",
                details: nil
            )
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            // Reserve the slot before the async work so a concurrent connect is
            // rejected rather than replacing this one.
            pendingConnects[deviceId] = PendingConnect(
                deviceId: deviceId,
                serviceUuid: serviceUuid,
                continuation: continuation
            )

            DispatchQueue.global(qos: .userInitiated).async {
                guard let device = IOBluetoothDevice(addressString: deviceId) else {
                    self.failPending(deviceId, PigeonError(code: "Failed", message: "Device not found", details: nil))
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
                        self.failPending(deviceId, PigeonError(code: "Failed", message: errorString, details: nil))
                        return
                    }
                }

                DispatchQueue.main.async {
                    let status = device.performSDPQuery(self)
                    if status != kIOReturnSuccess {
                        self.failPending(deviceId, PigeonError(
                            code: "SDPFailed",
                            message: "Failed to start SDP query",
                            details: nil
                        ))
                    }
                }
            }
        }
    }

    func disconnect(deviceId: String) async throws {
        guard let channel = rfcommChannels.removeValue(forKey: deviceId) else {
            return
        }
        channel.close()
        onConnectionUpdate(deviceId: deviceId, connected: false)
    }

    func send(deviceId: String, data: FlutterStandardTypedData) async throws {
        guard let channel = rfcommChannels[deviceId] else {
            throw PigeonError(code: "NotFound", message: "No serial connection for \(deviceId)", details: nil)
        }
        let bytes = [UInt8](data.data)
        // writeSync blocks until the peer accepts the bytes, so keep it off the
        // platform thread.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Self.write(bytes, to: channel)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Fails the pending connect for [deviceId], if one is still registered.
    private func failPending(_ deviceId: String, _ error: Error) {
        DispatchQueue.main.async {
            self.pendingConnects.removeValue(forKey: deviceId)?.continuation.resume(throwing: error)
        }
    }

    /// Writes [bytes] to [channel] in `UInt16`-sized chunks, since `writeSync`
    /// takes its length as a `UInt16` and a larger count would be truncated.
    private static func write(_ bytes: [UInt8], to channel: IOBluetoothRFCOMMChannel) throws {
        var offset = 0
        while offset < bytes.count {
            let chunkSize = min(bytes.count - offset, Int(UInt16.max))
            let result: IOReturn = bytes.withUnsafeBytes { bufferPointer in
                guard let baseAddress = bufferPointer.baseAddress else {
                    return kIOReturnError
                }
                return channel.writeSync(
                    UnsafeMutableRawPointer(mutating: baseAddress).advanced(by: offset),
                    length: UInt16(chunkSize)
                )
            }
            if result != kIOReturnSuccess {
                throw PigeonError(code: "Failed", message: "Failed to write to RFCOMM channel", details: nil)
            }
            offset += chunkSize
        }
    }

    /// Opens the RFCOMM channel once the SDP query for the service has completed.
    private func openRFCOMMChannel(device: IOBluetoothDevice, pending: PendingConnect) {
        guard let uuid = Self.sdpUUID(from: pending.serviceUuid) else {
            pending.continuation.resume(throwing: PigeonError(
                code: "InvalidUUID",
                message: "Invalid service UUID \(pending.serviceUuid)",
                details: nil
            ))
            return
        }

        guard let record = device.getServiceRecord(for: uuid) else {
            pending.continuation.resume(throwing: PigeonError(
                code: "ServiceNotFound",
                message: "Service \(pending.serviceUuid) not found on \(pending.deviceId)",
                details: nil
            ))
            return
        }

        var channelId: BluetoothRFCOMMChannelID = 0
        guard record.getRFCOMMChannelID(&channelId) == kIOReturnSuccess else {
            pending.continuation.resume(throwing: PigeonError(
                code: "SDPFailed",
                message: "Service \(pending.serviceUuid) has no RFCOMM channel",
                details: nil
            ))
            return
        }

        var channel: IOBluetoothRFCOMMChannel?
        let result = device.openRFCOMMChannelSync(&channel, withChannelID: channelId, delegate: self)
        guard result == kIOReturnSuccess, let openedChannel = channel else {
            let errorString = String(cString: mach_error_string(Int32(result)))
            pending.continuation.resume(throwing: PigeonError(
                code: "Failed",
                message: "Failed to open RFCOMM channel \(errorString)",
                details: nil
            ))
            return
        }

        rfcommChannels[pending.deviceId] = openedChannel
        onConnectionUpdate(deviceId: pending.deviceId, connected: true)
        pending.continuation.resume()
    }

    private func onConnectionUpdate(deviceId: String, connected: Bool) {
        Task {
            try? await callbackChannel.onConnectionStateChanged(
                deviceId: deviceId,
                connected: connected
            )
        }
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
    let continuation: CheckedContinuation<Void, any Error>
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
            pending.continuation.resume(throwing: PigeonError(
                code: "SDPFailed",
                message: "SDP query failed with status \(status)",
                details: nil
            ))
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
        Task {
            try? await callbackChannel.onData(
                deviceId: deviceId,
                data: FlutterStandardTypedData(bytes: data)
            )
        }
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel) {
        guard let deviceId = rfcommChannel.getDevice()?.addressString else { return }
        // Ignore the close of a channel that a newer connection has replaced, so
        // an old channel cannot tear down the current one.
        guard let current = rfcommChannels[deviceId], current === rfcommChannel else { return }
        rfcommChannels.removeValue(forKey: deviceId)
        onConnectionUpdate(deviceId: deviceId, connected: false)
    }
}
