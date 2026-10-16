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
import kotlinx.coroutines.CompletableDeferred

private const val TAG = "UniversalBluetoothPlugin"

typealias ConnectionFuture = CompletableDeferred<Unit>

@RequiresApi(Build.VERSION_CODES.P)
@SuppressLint("MissingPermission")
class BluetoothHidManager(
    private val context: Context,
    private val callbackChannel: BluetoothHidManagerCallbackChannel,
) : BluetoothHidManagerPlatformChannel, AndroidSdpChannel, BluetoothHidDevice.Callback() {
    private var initialized = false
    private var connectionFuture = mutableMapOf<String, ConnectionFuture>()
    private var disconnectionFuture = mutableMapOf<String, ConnectionFuture>()

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


    override suspend fun connect(deviceId: String) {
        val btHidProxy = btHidProxy
            ?: throw FlutterError("Failed", "BluetoothProxy not available")

        val bluetoothDevice = try {
            getBluetoothDeviceFromId(deviceId)
        } catch (e: Exception) {
            throw FlutterError(code = "Error", message = e.toString())
        }

        // Check if already connected
        val state = btHidProxy.getConnectionState(bluetoothDevice)
        if (state == BluetoothProfile.STATE_CONNECTING || state == BluetoothProfile.STATE_CONNECTED) {
            Log.d(TAG, "Already Connected")
            onConnectionResult(deviceId, true)
            return
        }
        if (connectionFuture[deviceId] != null) {
            throw FlutterError("Failed", "Connection already in progress")
        }

        // Make connection request
        val result = btHidProxy.connect(bluetoothDevice)

        if (!result) {
            throw FlutterError("Failed", "Failed to connect")
        }

        val currentState = btHidProxy.getConnectionState(bluetoothDevice)
        Log.d(TAG, "Current $deviceId state: ${currentState.toConnectionStateString()}")

        if (currentState == BluetoothProfile.STATE_CONNECTED) {
            Log.d(TAG, "Connected Already, no need to wait")
            onConnectionResult(deviceId, true)
            return
        }

        Log.d(TAG, "Waiting for connection result of $deviceId")
        // Wait for the connection confirmation
        val future = CompletableDeferred<Unit>()
        connectionFuture[deviceId] = future
        future.await()
    }


    override suspend fun disconnect(deviceId: String) {
        val btHidProxy = btHidProxy
            ?: throw FlutterError("Failed", "BluetoothProxy not available")

        val bluetoothDevice = try {
            getBluetoothDeviceFromId(deviceId)
        } catch (e: Exception) {
            throw FlutterError(code = "Error", message = e.toString())
        }

        // Check if already disconnected
        val state = btHidProxy.getConnectionState(bluetoothDevice)
        if (state == BluetoothProfile.STATE_DISCONNECTING || state == BluetoothProfile.STATE_DISCONNECTED) {
            Log.d(TAG, "Already Disconnected")
            // Call disconnect to release resources
            btHidProxy.disconnect(bluetoothDevice)
            onConnectionResult(deviceId, false)
            return
        }

        if (disconnectionFuture[deviceId] != null) {
            throw FlutterError("Failed", "Disconnection already in progress")
        }

        // Make disconnection request
        val result = btHidProxy.disconnect(bluetoothDevice)
        if (!result) {
            throw FlutterError("Failed", "Failed to disconnect")
        }

        // Wait for the disconnection confirmation
        val future = CompletableDeferred<Unit>()
        disconnectionFuture[deviceId] = future
        future.await()
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
        postCallback { callbackChannel.onConnectionStateChanged(deviceId, connected) }
        // Complete Future
        connectionFuture.remove(deviceId)?.let {
            if (connected) {
                it.complete(Unit)
            } else {
                it.completeExceptionally(FlutterError("Disconnected", "Device Disconnected"))
            }
        }
        // Complete Disconnection Future
        disconnectionFuture.remove(deviceId)?.let {
            if (connected) {
                it.completeExceptionally(FlutterError("Failed", "Device Connected"))
            } else {
                it.complete(Unit)
            }
        }
    }

    /// ---- BluetoothHidDeviceCallback ----
    override fun onGetReport(device: BluetoothDevice, type: Byte, id: Byte, bufferSize: Int) {
        Log.d(TAG, "onGetReport: device=$device type=$type id=$id bufferSize=$bufferSize")
        postCallback {
            val reply: ReportReply? = try {
                callbackChannel.onGetReport(device.address, type.toReportType(), bufferSize.toLong())
            } catch (e: Exception) {
                Log.e(TAG, "onGetReport callback failed", e)
                null
            }
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
        postCallback { callbackChannel.onSdpServiceRegistrationUpdate(registered) }
    }

    override fun onSetReport(device: BluetoothDevice?, type: Byte, id: Byte, data: ByteArray?) {
        Log.d(TAG, "onSetReport $device $type $id $data")
        // The host sent us a report. Forward the payload; the HID type/id are
        // not part of the unified data API.
        if (device != null && data != null) {
            postCallback { callbackChannel.onData(device.address, data) }
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
            postCallback { callbackChannel.onData(device.address, data) }
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