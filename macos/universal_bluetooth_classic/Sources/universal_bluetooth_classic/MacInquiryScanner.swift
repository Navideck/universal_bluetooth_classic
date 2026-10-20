import Foundation
import IOBluetooth

/// Runs macOS Bluetooth Classic inquiries and resolves device names.
///
/// `IOBluetoothDeviceInquiry` only runs for `inquiryLength` seconds and macOS
/// reports devices before their names are known. This scanner keeps a scan
/// requested across inquiry rounds, resolves names between rounds, and reports
/// a device when it is first seen and again when its name changes, so
/// name-filtered listeners receive the device once the name is available.
final class MacInquiryScanner: NSObject {
    typealias DeviceHandler = (IOBluetoothDevice) -> Void

    var onDeviceFound: DeviceHandler?

    private lazy var inquiry: IOBluetoothDeviceInquiry = .init(delegate: self)
    private(set) var isScanning = false

    /// Bumped whenever a scan session starts or stops, so completions that
    /// belong to a previous session can be ignored.
    private var sessionGeneration = 0
    /// Bumped whenever a restart is scheduled; older timers are discarded.
    private var restartGeneration = 0
    /// Session that started the inquiry currently in flight.
    private var inquirySession = 0
    private var isInquiryRunning = false
    private var pendingNameRequests: Set<String> = []
    /// Last name reported per address, so a device is not reported again on
    /// every inquiry round.
    private var reportedNames: [String: String] = [:]

    private let inquiryLengthSeconds: UInt8 = 5
    private let inquiryRestartDelay: TimeInterval = 1
    /// Page timeout for remote name requests, kept well below
    /// `nameRequestTimeout` so a request finishes before the inquiry restarts.
    private let nameRequestPageTimeoutSeconds: TimeInterval = 3
    /// Upper bound for waiting on name requests before restarting the inquiry.
    private let nameRequestTimeout: TimeInterval = 8

    func start() throws {
        guard !isScanning else { return }
        sessionGeneration += 1
        isScanning = true
        pendingNameRequests.removeAll()
        reportedNames.removeAll()
        invalidatePendingRestart()
        do {
            try startInquiry()
        } catch {
            isScanning = false
            throw error
        }
    }

    func stop() {
        sessionGeneration += 1
        isScanning = false
        isInquiryRunning = false
        pendingNameRequests.removeAll()
        invalidatePendingRestart()
        inquiry.stop()
    }

    private func startInquiry() throws {
        // Requests that are still pending when the next round starts will not
        // be reported; the next round looks the devices up again.
        pendingNameRequests.removeAll()
        inquiry.updateNewDeviceNames = false
        inquiry.inquiryLength = inquiryLengthSeconds
        let result = inquiry.start()
        guard result == kIOReturnSuccess else {
            isInquiryRunning = false
            throw MacInquiryError.failedToStart(result)
        }
        inquirySession = sessionGeneration
        isInquiryRunning = true
    }

    private func scheduleRestart(after delay: TimeInterval? = nil) {
        restartGeneration += 1
        let generation = restartGeneration
        let restartDelay = delay ?? inquiryRestartDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + restartDelay) { [weak self] in
            guard let self, self.isScanning, self.restartGeneration == generation else {
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
        restartGeneration += 1
    }

    /// macOS reports devices before it resolves their names, and sometimes the
    /// name stays equal to the address for the whole inquiry. Request names once
    /// the inquiry has stopped (remote name requests must not run while an
    /// inquiry is active), then report them from `remoteNameRequestComplete`.
    private func requestNamesForUnresolvedDevices() {
        guard let devices = inquiry.foundDevices() as? [IOBluetoothDevice] else {
            return
        }
        let pageTimeout = UInt16(round(nameRequestPageTimeoutSeconds * 1600))
        for device in devices where !Self.hasResolvedName(device) {
            guard let address = device.addressString else { continue }
            // A request for this address is already outstanding; issuing a
            // second one would produce duplicate callbacks.
            guard pendingNameRequests.insert(address).inserted else { continue }
            if device.remoteNameRequest(self, withPageTimeout: pageTimeout) != kIOReturnSuccess {
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
        guard let address = device.addressString else { return }
        let name = device.name ?? ""
        guard reportedNames[address] != name else { return }
        reportedNames[address] = name
        onDeviceFound?(device)
    }
}

extension MacInquiryScanner: IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryComplete(
        _: IOBluetoothDeviceInquiry,
        error: IOReturn,
        aborted: Bool
    ) {
        // A completion for an inquiry from a stopped (or restarted) session
        // must not overwrite the state of the inquiry that replaced it.
        if aborted, inquirySession != sessionGeneration {
            return
        }
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
        // A request that belongs to a stopped or restarted scan is no longer
        // tracked; ignoring it keeps discovery from firing after `stopScan()`.
        guard pendingNameRequests.remove(address) != nil, isScanning else { return }
        if status == kIOReturnSuccess {
            report(device)
        }
        if !isInquiryRunning, pendingNameRequests.isEmpty {
            scheduleRestart()
        }
    }

    func connectionComplete(_: IOBluetoothDevice, status _: IOReturn) {}

    func sdpQueryComplete(_: IOBluetoothDevice, status _: IOReturn) {}
}

enum MacInquiryError: Error {
    case failedToStart(IOReturn)
}
