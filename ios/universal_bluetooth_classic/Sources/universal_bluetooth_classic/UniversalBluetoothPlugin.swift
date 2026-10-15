import ExternalAccessory
import Flutter
import UIKit

public class UniversalBluetoothPlugin: NSObject, FlutterPlugin, ExternalAccessoryChannel {
  var callbackChannel: ExternalAccessoryCallbackChannel
  private let manager = EAAccessoryManager.shared()
  private var sessionControllers = [String: EASessionController]()
  /// Connection IDs for which a `disconnected` event has already been sent
  /// since the last connect / session open. Prevents a session failure and the
  /// accessory-level disconnect notification from both reporting the same
  /// disconnect.
  private var reportedDisconnected = Set<Int>()

  init(callbackChannel: ExternalAccessoryCallbackChannel) {
    self.callbackChannel = callbackChannel
    manager.registerForLocalNotifications()
    super.init()

    NotificationCenter.default.addObserver(self, selector: #selector(accessoryConnected(_:)), name: NSNotification.Name.EAAccessoryDidConnect, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(accessoryDisconnected(_:)), name: NSNotification.Name.EAAccessoryDidDisconnect, object: nil)
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    let messenger: FlutterBinaryMessenger = registrar.messenger()
    let callbackChannel = ExternalAccessoryCallbackChannel(binaryMessenger: messenger)
    let instance = UniversalBluetoothPlugin(callbackChannel: callbackChannel)
    ExternalAccessoryChannelSetup.setUp(binaryMessenger: messenger, api: instance)
  }

  func showBluetoothAccessoryPicker(withNames: [String], completion: @escaping (Result<Void, any Error>) -> Void) {
    var compoundPredicate: NSCompoundPredicate? = nil
    if !withNames.isEmpty {
      // Matches strings that start with the specified value. [c] makes the comparison case-insensitive.
      let predicates = withNames.map { NSPredicate(format: "SELF BEGINSWITH[c] %@", $0) }  
      compoundPredicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }
    // The system picker does not present under the UIScene lifecycle. See
    // EABluetoothAccessoryPickerWorkaround for details.
    let pickerSession = EABluetoothAccessoryPickerWorkaround.begin()
    manager.showBluetoothAccessoryPicker(withNameFilter: compoundPredicate) { error in
      EABluetoothAccessoryPickerWorkaround.end(pickerSession)
      if let error = error {
        // Error Codes:
        // alreadyConnected = 0
        // resultNotFound = 1
        // resultCancelled = 2
        // resultFailed = 3
        var code = "-1"
        if let error = error as? EABluetoothAccessoryPickerError {
          code = "\(error.code.rawValue)"
        }
        completion(.failure(PigeonError(code: code, message: error.localizedDescription, details: nil)))
      } else {
        completion(.success(()))
      }
    }
  }

  func openSession(protocolString: String, completion: @escaping (Result<Void, any Error>) -> Void) {
    guard sessionControllers[protocolString] == nil else {
      completion(.failure(ExternalAccessorySessionError.sessionAlreadyOpen))
      return
    }

    // Find the connected accessory that advertises this protocol.
    guard let accessory = manager.connectedAccessories.first(where: {
      $0.protocolStrings.contains(protocolString)
    }) else {
      completion(.failure(ExternalAccessorySessionError.accessoryNotFound))
      return
    }

    // Opening a session for the accessory starts a new connection episode, so
    // a future disconnect must be reported again.
    reportedDisconnected.remove(accessory.connectionID)

    guard let controller = EASessionController(accessory: accessory, protocolString: protocolString) else {
      completion(.failure(ExternalAccessorySessionError.sessionCreationFailed))
      return
    }

    controller.onData = { [weak self] data in
      self?.callbackChannel.onData(
        protocolString: protocolString,
        data: FlutterStandardTypedData(bytes: data)
      ) { _ in }
    }
    controller.onFinished = { [weak self] in
      self?.sessionDidFinish(protocolString: protocolString, accessory: accessory)
    }

    sessionControllers[protocolString] = controller
    controller.open()
    completion(.success(()))
  }

  func send(protocolString: String, data: FlutterStandardTypedData, completion: @escaping (Result<Void, any Error>) -> Void) {
    guard let controller = sessionControllers[protocolString] else {
      completion(.failure(ExternalAccessorySessionError.sessionNotOpen))
      return
    }
    controller.write(data.data)
    completion(.success(()))
  }

  func closeSession(protocolString: String?, completion: @escaping (Result<Void, any Error>) -> Void) {
    // An explicit protocol string closes that session; omitting it closes every
    // open session. Closing an already-closed session is a no-op.
    let protocols = protocolString.map { [$0] } ?? Array(sessionControllers.keys)
    for protocolString in protocols {
      sessionControllers.removeValue(forKey: protocolString)?.close()
    }
    completion(.success(()))
  }

  /// Handles a session whose streams ended on their own.
  private func sessionDidFinish(protocolString: String, accessory: ExternalAccessory.EAAccessory) {
    guard sessionControllers.removeValue(forKey: protocolString) != nil else { return }
    // Only surface a disconnect when the accessory is still physically
    // connected: that means the session failed on its own. When the accessory
    // itself disconnected, `accessoryDisconnected` already reported it and
    // `accessory.isConnected` is false.
    let connectionID = accessory.connectionID
    guard accessory.isConnected, !reportedDisconnected.contains(connectionID) else { return }
    reportedDisconnected.insert(connectionID)
    callbackChannel.onConnectionStateChanged(
      accessory: accessory.toEAAccessoryObject(),
      connected: false
    ) { _ in }
  }

  @objc private func accessoryConnected(_ notification: NSNotification) {
    guard let connectedAccessory = notification.userInfo?[EAAccessoryKey] as? ExternalAccessory.EAAccessory else { return }
    reportedDisconnected.remove(connectedAccessory.connectionID)
    callbackChannel.onConnectionStateChanged(
      accessory: connectedAccessory.toEAAccessoryObject(),
      connected: true
    ) { _ in }
  }

  @objc private func accessoryDisconnected(_ notification: NSNotification) {
    guard let connectedAccessory = notification.userInfo?[EAAccessoryKey] as? ExternalAccessory.EAAccessory else { return }
    // Tear down any session opened for the accessory's protocols.
    for protocolString in connectedAccessory.protocolStrings {
      sessionControllers.removeValue(forKey: protocolString)?.close()
    }
    // A session failure may already have reported this disconnect; only emit
    // once per connection episode.
    let connectionID = connectedAccessory.connectionID
    guard !reportedDisconnected.contains(connectionID) else { return }
    reportedDisconnected.insert(connectionID)
    callbackChannel.onConnectionStateChanged(
      accessory: connectedAccessory.toEAAccessoryObject(),
      connected: false
    ) { _ in }
  }
}

enum ExternalAccessorySessionError: Error {
  case accessoryNotFound
  case sessionCreationFailed
  case sessionAlreadyOpen
  case sessionNotOpen
}

extension ExternalAccessory.EAAccessory {
  func toEAAccessoryObject() -> EAAccessory {
    return EAAccessory(
      isConnected: isConnected,
      connectionID: Int64(connectionID),
      manufacturer: manufacturer,
      name: name,
      modelNumber: modelNumber,
      serialNumber: serialNumber,
      firmwareRevision: firmwareRevision,
      hardwareRevision: hardwareRevision,
      dockType: dockType,
      protocolStrings: protocolStrings
    )
  }
}
