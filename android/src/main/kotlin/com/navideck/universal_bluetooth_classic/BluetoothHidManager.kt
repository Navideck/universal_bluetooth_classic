package com.navideck.universal_bluetooth_classic

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothHidDeviceAppQosSettings
import android.bluetooth.BluetoothHidDeviceAppSdpSettings
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothProfile.ServiceListener
import android.content.Context
import android.os.Build
import android.util.Log
import androidx.annotation.RequiresApi

private const val TAG = "UniversalBluetoothPlugin"

typealias ConnectionCallback = (Result<Unit>) -> Unit

@RequiresApi(Build.VERSION_CODES.P)
@SuppressLint("MissingPermission")
class BluetoothHidManager(
    private val context: Context,
    private val callbackChannel: BluetoothHidManagerCallbackChannel,
) : BluetoothHidManagerPlatformChannel, AndroidSdpChannel, BluetoothHidDevice.Callback() {
    private var initialized = false
    private val connectionCallbacks = mutableMapOf<String, ConnectionCallback>()
    private val disconnectionCallbacks = mutableMapOf<String, ConnectionCallback>()

    override fun setupSdp(config: AndroidSdpConfig) {
        if (initialized) {
            throw FlutterError("AlreadyInitialized", "BluetoothProxyProfile already initialized")
        }
        // Initialize profile and setup listener
        val result = bluetoothAdapter?.getProfileProxy(
            context, object : ServiceListener {
                override fun onServiceConnected(profile: Int, proxy: BluetoothProfile?) {
                    if (profile != BluetoothProfile.HID_DEVICE) return
                    Log.d(TAG, "Got HID device")
                    btHidProxy = proxy as BluetoothHidDevice
                    btHidProxy?.registerApp(
                        config.toSdp(),
                        null,
                        BluetoothHidDeviceAppQosSettings(
                            BluetoothHidDeviceAppQosSettings.SERVICE_BEST_EFFORT,
                            800,
                            9,
                            0,
                            11250,
                            BluetoothHidDeviceAppQosSettings.MAX
                        ),
                        Runnable::run,
                        this@BluetoothHidManager
                    )
                }

                override fun onServiceDisconnected(profile: Int) {
                    if (profile != BluetoothProfile.HID_DEVICE) return
                    Log.e(TAG, "Lost HID device")
                    btHidProxy?.unregisterApp()
                    btHidProxy = null
                }
            },
            BluetoothProfile.HID_DEVICE
        )

        if (result != true) {
            throw FlutterError("Failed", "Failed to register hid profile")
        }
        initialized = true
    }

    override fun closeSdp() {
        initialized = false
        btHidProxy?.let {
            it.unregisterApp()
            bluetoothAdapter?.closeProfileProxy(BluetoothProfile.HID_DEVICE, it)
        }
        btHidProxy = null
    }


    override fun connect(deviceId: String, callback: ConnectionCallback) {
        try {
            val btHidProxy = btHidProxy
            if (btHidProxy == null) {
                callback(Result.failure(FlutterError("Failed", "BluetoothProxy not available")))
                return
            }

            val bluetoothDevice = try {
                getBluetoothDeviceFromId(deviceId)
            } catch (e: Exception) {
                callback(Result.failure(FlutterError(code = "Error", message = e.toString())))
                return
            }

            // Check if already connected
            val state = btHidProxy.getConnectionState(bluetoothDevice)
            if (state == BluetoothProfile.STATE_CONNECTING || state == BluetoothProfile.STATE_CONNECTED) {
                Log.d(TAG, "Already Connected")
                onConnectionResult(deviceId, true)
                callback(Result.success(Unit))
                return
            }
            if (connectionCallbacks.containsKey(deviceId)) {
                callback(Result.failure(FlutterError("Failed", "Connection already in progress")))
                return
            }

            // Make connection request
            if (!btHidProxy.connect(bluetoothDevice)) {
                callback(Result.failure(FlutterError("Failed", "Failed to connect")))
                return
            }

            val currentState = btHidProxy.getConnectionState(bluetoothDevice)
            Log.d(TAG, "Current $deviceId state: ${currentState.toConnectionStateString()}")

            if (currentState == BluetoothProfile.STATE_CONNECTED) {
                Log.d(TAG, "Connected Already, no need to wait")
                onConnectionResult(deviceId, true)
                callback(Result.success(Unit))
                return
            }

            Log.d(TAG, "Waiting for connection result of $deviceId")
            // Wait for the connection confirmation
            connectionCallbacks[deviceId] = callback
        } catch (e: Exception) {
            // The BluetoothHidDevice proxy calls above can throw (for example a
            // SecurityException when BLUETOOTH_CONNECT is not granted). Convert
            // that into a failure reply so the caller does not wait forever.
            callback(Result.failure(FlutterError(code = "Error", message = e.toString())))
        }
    }


    override fun disconnect(deviceId: String, callback: ConnectionCallback) {
        try {
            val btHidProxy = btHidProxy
            if (btHidProxy == null) {
                callback(Result.failure(FlutterError("Failed", "BluetoothProxy not available")))
                return
            }

            val bluetoothDevice = try {
                getBluetoothDeviceFromId(deviceId)
            } catch (e: Exception) {
                callback(Result.failure(FlutterError(code = "Error", message = e.toString())))
                return
            }

            // Check if already disconnected
            val state = btHidProxy.getConnectionState(bluetoothDevice)
            if (state == BluetoothProfile.STATE_DISCONNECTING || state == BluetoothProfile.STATE_DISCONNECTED) {
                Log.d(TAG, "Already Disconnected")
                // Call disconnect to release resources
                btHidProxy.disconnect(bluetoothDevice)
                onConnectionResult(deviceId, false)
                callback(Result.success(Unit))
                return
            }

            if (disconnectionCallbacks.containsKey(deviceId)) {
                callback(Result.failure(FlutterError("Failed", "Disconnection already in progress")))
                return
            }

            // Make disconnection request
            if (!btHidProxy.disconnect(bluetoothDevice)) {
                callback(Result.failure(FlutterError("Failed", "Failed to disconnect")))
                return
            }

            // Wait for the disconnection confirmation
            disconnectionCallbacks[deviceId] = callback
        } catch (e: Exception) {
            // See connect: a proxy exception must still complete the callback.
            callback(Result.failure(FlutterError(code = "Error", message = e.toString())))
        }
    }

    override fun send(deviceId: String, data: ByteArray) {
        val device = btHidProxy?.connectedDevices?.firstOrNull { it.address == deviceId }
            ?: throw FlutterError("NotFound", "Device not connected")
        val result = btHidProxy?.sendReport(device, 0, data) ?: false
        if (!result) {
            throw FlutterError("Failed", "Failed to send report")
        }
    }

    private fun onConnectionResult(deviceId: String, connected: Boolean) {
        // Update Flutter
        postCallback { callbackChannel.onConnectionStateChanged(deviceId, connected) { _ -> } }
        // Complete connection callback
        connectionCallbacks.remove(deviceId)?.let {
            if (connected) {
                it(Result.success(Unit))
            } else {
                it(Result.failure(FlutterError("Disconnected", "Device Disconnected")))
            }
        }
        // Complete disconnection callback
        disconnectionCallbacks.remove(deviceId)?.let {
            if (connected) {
                it(Result.failure(FlutterError("Failed", "Device Connected")))
            } else {
                it(Result.success(Unit))
            }
        }
    }

    /// ---- BluetoothHidDeviceCallback ----
    override fun onGetReport(device: BluetoothDevice, type: Byte, id: Byte, bufferSize: Int) {
        Log.d(TAG, "onGetReport: device=$device type=$type id=$id bufferSize=$bufferSize")
        postCallback {
            callbackChannel.onGetReport(device.address, type.toReportType(), bufferSize.toLong()) { result ->
                val reply: ReportReply? = result.getOrNull()
                if (reply == null) {
                    btHidProxy?.reportError(device, BluetoothHidDevice.ERROR_RSP_UNSUPPORTED_REQ)
                } else if (reply.error != null) {
                    btHidProxy?.reportError(device, reply.error.toByte())
                } else if (reply.data != null) {
                    btHidProxy?.replyReport(device, type, id, reply.data)
                } else {
                    btHidProxy?.reportError(device, BluetoothHidDevice.ERROR_RSP_UNKNOWN)
                }
            }
        }
    }

    override fun onConnectionStateChanged(device: BluetoothDevice, state: Int) {
        Log.d(
            TAG,
            "onConnectionStateChanged: device=$device state=${state.toConnectionStateString()}"
        )
        if (state == BluetoothProfile.STATE_CONNECTED) {
            onConnectionResult(device.address, true)
        } else if (state == BluetoothProfile.STATE_DISCONNECTED) {
            onConnectionResult(device.address, false)
        }
    }

    override fun onAppStatusChanged(pluggedDevice: BluetoothDevice?, registered: Boolean) {
        Log.d(TAG, "onAppStatusChanged $pluggedDevice $registered")
        postCallback { callbackChannel.onSdpServiceRegistrationUpdate(registered) { _ -> } }
    }

    override fun onSetReport(device: BluetoothDevice?, type: Byte, id: Byte, data: ByteArray?) {
        Log.d(TAG, "onSetReport $device $type $id $data")
        // The host sent us a report. Forward the payload; the HID type/id are
        // not part of the unified data API.
        if (device != null && data != null) {
            postCallback { callbackChannel.onData(device.address, data) { _ -> } }
        }
        btHidProxy?.reportError(device, BluetoothHidDevice.ERROR_RSP_SUCCESS);
    }

    override fun onSetProtocol(device: BluetoothDevice?, protocol: Byte) {
        Log.d(TAG, "onSetProtocol $device $protocol")
        when (protocol) {
            BluetoothHidDevice.PROTOCOL_BOOT_MODE -> Log.d(TAG, "Protocol set to Boot Protocol")
            BluetoothHidDevice.PROTOCOL_REPORT_MODE -> Log.d(TAG, "Protocol set to Report Protocol")
            else -> {}
        }
    }

    override fun onInterruptData(device: BluetoothDevice?, reportId: Byte, data: ByteArray?) {
        Log.d(TAG, "onInterruptData $device $reportId $data")
        if (device != null && data != null) {
            postCallback { callbackChannel.onData(device.address, data) { _ -> } }
        }
    }

    override fun onVirtualCableUnplug(device: BluetoothDevice?) {
        Log.d(TAG, "onVirtualCableUnplug $device")
    }
    /// ---- BluetoothHidDeviceCallback ----


    private fun AndroidSdpConfig.toSdp(): BluetoothHidDeviceAppSdpSettings {
        return BluetoothHidDeviceAppSdpSettings(
            name,
            description,
            provider,
            subclass.toByte(),
            descriptors
        )
    }

    private fun Byte.toReportType(): ReportType {
        return when (this) {
            BluetoothHidDevice.REPORT_TYPE_FEATURE -> ReportType.FEATURE
            BluetoothHidDevice.REPORT_TYPE_INPUT -> ReportType.INPUT
            BluetoothHidDevice.REPORT_TYPE_OUTPUT -> ReportType.OUTPUT
            else -> ReportType.FEATURE
        }
    }

    private fun Int.toConnectionStateString(): String {
        return when (this) {
            BluetoothProfile.STATE_CONNECTING -> "STATE_CONNECTING"
            BluetoothProfile.STATE_CONNECTED -> "STATE_CONNECTED"
            BluetoothProfile.STATE_DISCONNECTING -> "STATE_DISCONNECTING"
            BluetoothProfile.STATE_DISCONNECTED -> "STATE_DISCONNECTED"
            else -> "UNKNOWN"
        }
    }

}
