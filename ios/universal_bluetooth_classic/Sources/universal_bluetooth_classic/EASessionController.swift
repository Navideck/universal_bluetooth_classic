import ExternalAccessory
import Foundation

/// Owns a single Apple External Accessory session (one accessory and one
/// protocol) and moves bytes between its streams and Flutter.
///
/// The session's streams are scheduled on the main run loop, so delegate
/// callbacks are delivered on the main thread and can be forwarded to Flutter
/// directly. External Accessory accessories (serial devices) are low-bandwidth,
/// so the main thread is sufficient.
final class EASessionController: NSObject, StreamDelegate {
  /// The protocol string this session was opened for.
  let protocolString: String

  /// Called with bytes received from the accessory.
  var onData: ((Data) -> Void)?

  /// Called once when the session ends on its own (stream error or end of
  /// stream). Never called after an explicit ``close()``.
  var onFinished: (() -> Void)?

  private let session: EASession
  private var isOpen = false
  private var pendingWrite = Data()

  /// Creates a controller for `accessory`/`protocolString`, or `nil` when the
  /// session cannot be created.
  init?(accessory: ExternalAccessory.EAAccessory, protocolString: String) {
    guard let session = EASession(accessory: accessory, forProtocol: protocolString) else {
      return nil
    }
    self.session = session
    self.protocolString = protocolString
    super.init()
  }

  /// Opens the session's streams.
  func open() {
    guard !isOpen else { return }
    isOpen = true
    for stream in streams {
      stream.delegate = self
      stream.schedule(in: .main, forMode: .default)
      stream.open()
    }
  }

  /// Queues `data` to be written to the accessory.
  func write(_ data: Data) {
    guard isOpen, !data.isEmpty else { return }
    pendingWrite.append(data)
    flush()
  }

  /// Closes the session's streams. Idempotent.
  func close() {
    guard isOpen else { return }
    isOpen = false
    pendingWrite.removeAll()
    for stream in streams {
      stream.delegate = nil
      stream.close()
    }
  }

  // MARK: - StreamDelegate

  func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
    switch eventCode {
    case .hasBytesAvailable:
      readAvailableBytes()
    case .hasSpaceAvailable:
      flush()
    case .errorOccurred, .endEncountered:
      finish()
    default:
      break
    }
  }

  // MARK: - Private

  private var streams: [Stream] {
    [session.inputStream, session.outputStream].compactMap { $0 }
  }

  /// Writes as much of `pendingWrite` as the output stream will accept.
  private func flush() {
    guard isOpen, let output = session.outputStream else { return }
    while !pendingWrite.isEmpty && output.hasSpaceAvailable {
      let written = pendingWrite.withUnsafeBytes { buffer -> Int in
        guard let base = buffer.bindMemory(to: UInt8.self).baseAddress else {
          return 0
        }
        return output.write(base, maxLength: pendingWrite.count)
      }
      guard written > 0 else { return }
      pendingWrite.removeFirst(written)
    }
  }

  /// Drains everything currently buffered on the input stream.
  private func readAvailableBytes() {
    guard let input = session.inputStream else { return }
    var buffer = [UInt8](repeating: 0, count: 1024)
    while input.hasBytesAvailable {
      let count = input.read(&buffer, maxLength: buffer.count)
      guard count > 0 else { return }
      onData?(Data(buffer[0..<count]))
    }
  }

  private func finish() {
    guard isOpen else { return }
    close()
    onFinished?()
  }
}
