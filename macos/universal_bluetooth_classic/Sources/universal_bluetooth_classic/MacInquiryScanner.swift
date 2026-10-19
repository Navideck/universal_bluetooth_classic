import Foundation
import IOBluetooth

/// Runs macOS Bluetooth Classic inquiries and resolves device names.
///
/// `IOBluetoothDeviceInquiry` only runs for `inquiryLength` seconds and macOS
/// reports devices before their names are known. This scanner keeps a scan
/// requested across inquiry rounds, resolves names between rounds, and reports
/// each device once its name is available.
final class MacInquiryScanner: NSObject {
    typealias DeviceHandler = (IOBluetoothDevice) -> Void

    var onDeviceFound: DeviceHandler?

    private lazy var inquiry: IOBluetoothDeviceInquiry = .init(delegate: self)
    private(set) var isScanning = false

    private var scanGeneration = 0
    private var isInquiryRunning = false
    private var pendingNameRequests: Set<String> = []

    private let inquiryLengthSeconds: UInt8 = 5
    private let inquiryRestartDelay: TimeInterval = 1
    private let nameRequestTimeout: TimeInterval = 8

    func start() throws {
        guard !isScanning else { return }
        isScanning = true
        invalidatePendingRestart()
        do {
            try startInquiry()
        } catch {
            isScanning = false
            throw error
        }
    }

    func stop() {
        isScanning = false
        isInquiryRunning = false
        invalidatePendingRestart()
        inquiry.stop()
    }

    private func startInquiry() throws {
        inquiry.updateNewDeviceNames = false
        inquiry.inquiryLength = inquiryLengthSeconds
        let result = inquiry.start()
        guard result == kIOReturnSuccess else {
            isInquiryRunning = false
            throw MacInquiryError.failedToStart(result)
        }
        isInquiryRunning = true
    }

    private func scheduleRestart(after delay: TimeInterval? = nil) {
        scanGeneration += 1
        let generation = scanGeneration
        let restartDelay = delay ?? inquiryRestartDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay) { [weak self] in
            guard let self, self.isScanning, self.scanGeneration == generation else {
                return
            }
            do {
                try self.startInquiry()
            } catch {
                print("Failed to restart inquiry: \(error)")
                self.scheduleRestart()
            }
        }
    }

    private func invalidatePendingRestart() {
        scanGeneration += 1
    }

    /// macOS reports devices before it resolves their names, and sometimes the
    /// name stays equal to the address for the whole inquiry. Request names once
    /// the inquiry has stopped (remote name requests must not run while an
    /// inquiry is active), then report them from `remoteNameRequestComplete`.
    private func requestNamesForUnresolvedDevices() {
        guard let devices = inquiry.foundDevices() as? [IOBluetoothDevice] else {
            return
        }
        for device in devices where !Self.hasResolvedName(device) {
            guard let address = device.addressString else { continue }
            pendingNameRequests.insert(address)
            if device.remoteNameRequest(self) != kIOReturnSuccess {
                pendingNameRequests.remove(address)
            }
        }
    }

    private static func hasResolvedName(_ device: IOBluetoothDevice) -> Bool {
        guard let name = device.name, !name.isEmpty, let address = device.addressString else {
            return false
        }
        let normalizedName = name
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        let normalizedAddress = address
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
        return normalizedName.caseInsensitiveCompare(normalizedAddress) != .orderedSame
    }

    private func report(_ device: IOBluetoothDevice) {
        onDeviceFound?(device)
    }
}

extension MacInquiryScanner: IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryComplete(
        _: IOBluetoothDeviceInquiry,
        error: IOReturn,
        aborted: Bool
    ) {
        isInquiryRunning = false
        if error != kIOReturnSuccess && !aborted {
            print("Inquiry failed with error: \(error)")
        }
        guard isScanning, !aborted else { return }
        requestNamesForUnresolvedDevices()
        scheduleRestart(after: pendingNameRequests.isEmpty ? nil : nameRequestTimeout)
    }

    func deviceInquiryDeviceFound(
        _: IOBluetoothDeviceInquiry,
        device: IOBluetoothDevice
    ) {
        report(device)
    }
}

extension MacInquiryScanner: IOBluetoothDeviceAsyncCallbacks {
    func remoteNameRequestComplete(_ device: IOBluetoothDevice, status: IOReturn) {
        guard let address = device.addressString else { return }
        pendingNameRequests.remove(address)
        if status == kIOReturnSuccess {
            report(device)
        }
        if isScanning, !isInquiryRunning, pendingNameRequests.isEmpty {
            scheduleRestart()
        }
    }

    func connectionComplete(_: IOBluetoothDevice, status _: IOReturn) {}

    func sdpQueryComplete(_: IOBluetoothDevice, status _: IOReturn) {}
}

enum MacInquiryError: Error {
    case failedToStart(IOReturn)
}
