import ExternalAccessory
import Flutter
import UIKit

public class UniversalBluetoothPlugin: NSObject, FlutterPlugin, ExternalAccessoryChannel {
  var callbackChannel: ExternalAccessoryCallbackChannel
  private var manager = EAAccessoryManager.shared()
  private var eaSessionDisconnectionCompleterMap = [String: (Result<Void, any Error>) -> Void]()

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
    manager.showBluetoothAccessoryPicker(withNameFilter: compoundPredicate) { error in
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

  func closeEASession(protocolString: String? = nil, completion: @escaping (Result<Void, Error>) -> Void) {
      enum SessionError: Error {
          case alreadyInProgress
          case accessoryNotFound
          case sessionCreationFailed
          case noProtocolStringsAvailable
      }
      
      // Determine the protocol string to use
      let effectiveProtocolString: String
      if let protocolString = protocolString {
          effectiveProtocolString = protocolString
      } else {
          // Find first accessory and get its first protocol string
          guard let firstAccessory = manager.connectedAccessories.last,
                let firstProtocolString = firstAccessory.protocolStrings.first else {
              completion(.failure(SessionError.noProtocolStringsAvailable))
              return
          }
          effectiveProtocolString = firstProtocolString
      }
      
      // Guard against existing session
      guard eaSessionDisconnectionCompleterMap[effectiveProtocolString] == nil else {
          completion(.failure(SessionError.alreadyInProgress))
          return
      }
      
      // Find matching accessory
      guard let accessory = manager.connectedAccessories.first(where: {
          $0.protocolStrings.contains(effectiveProtocolString)
      }) else {
          completion(.failure(SessionError.accessoryNotFound))
          return
      }
      
      // Create and validate session
      guard let session = EASession(accessory: accessory, forProtocol: effectiveProtocolString) else {
          completion(.failure(SessionError.sessionCreationFailed))
          return
      }
      
      // Store completion handler
      eaSessionDisconnectionCompleterMap[effectiveProtocolString] = completion
      
      // Schedule session cleanup
      DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          session.inputStream?.close()
          session.outputStream?.close()
      }
  }

  @objc private func accessoryConnected(_ notification: NSNotification) {
    let connectedAccessory = notification.userInfo![EAAccessoryKey] as? EAAccessory
    guard let connectedAccessory else { return }
    callbackChannel.accessoryConnected(accessory: connectedAccessory.toEAAccessoryObject()) { _ in }
  }

  @objc private func accessoryDisconnected(_ notification: NSNotification) {
    let connectedAccessory = notification.userInfo![EAAccessoryKey] as? EAAccessory
    guard let connectedAccessory else { return }
    for protocolString in connectedAccessory.protocolStrings {
      eaSessionDisconnectionCompleterMap.removeValue(forKey: protocolString)?(.success(()))
    }
    callbackChannel.accessoryDisconnected(accessory: connectedAccessory.toEAAccessoryObject()) { _ in }
  }
}

extension EAAccessory {
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
