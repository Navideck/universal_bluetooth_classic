## 0.2.0

* Replace the iOS-only `closeEASession` API with the unified `disconnect` API.
  The identifier is optional for iOS External Accessory sessions.
* Replace the iOS-only `accessoryConnected` and `accessoryDisconnected`
  callbacks with typed, cross-platform `BluetoothConnectionEvent` values from
  `onConnectionStateChanged`.
* Add iOS External Accessory and Linux BlueZ connection events.

## 0.1.0

* Initial release as `universal_bluetooth`.
