import Foundation
import IOBluetooth

/// Opens a classic connection (and bonds when necessary) with a discovered
/// device.
///
/// The first page right after discovery can time out, especially when a device
/// has just switched from BLE to classic discoverable mode, so the page uses a
/// generous timeout and is retried.
enum MacPairer {
    static let maxAttempts = 3
    static let pageTimeoutSeconds = 10.0
    static let retryDelay: TimeInterval = 1

    static func pair(
        address: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        DispatchQueue.global(qos: .background).async {
            guard let device = IOBluetoothDevice(addressString: address) else {
                completion(.failure(MacPairError.deviceNotFound(address)))
                return
            }

            var lastError = MacPairError.deviceNotFound(address)
            for attempt in 1...maxAttempts {
                if device.isConnected() {
                    completion(.success(true))
                    return
                }

                let result = device.openConnection(
                    nil,
                    withPageTimeout: UInt16(round(pageTimeoutSeconds * 1600)),
                    authenticationRequired: true
                )
                if result == kIOReturnSuccess {
                    completion(.success(true))
                    return
                }

                lastError = MacPairError.connectionFailed(
                    result,
                    String(cString: mach_error_string(Int32(result)))
                )
                print("Pair attempt \(attempt) for \(address) failed: \(lastError)")
                if attempt < maxAttempts {
                    Thread.sleep(forTimeInterval: retryDelay)
                }
            }
            completion(.failure(lastError))
        }
    }
}

enum MacPairError: Error, CustomStringConvertible {
    case deviceNotFound(String)
    case connectionFailed(IOReturn, String)

    var description: String {
        switch self {
        case .deviceNotFound(let address):
            return "Device not found: \(address)"
        case .connectionFailed(let code, let message):
            return "\(message) (\(code))"
        }
    }
}
