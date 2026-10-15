package com.navideck.universal_bluetooth_classic

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.util.Log
import java.io.IOException
import java.util.UUID

private const val SERIAL_TAG = "BluetoothSerialManager"

/**
 * Generic serial (SPP/RFCOMM) transport. Opens a [BluetoothSocket] to a remote
 * device for a service UUID and forwards the byte stream to Flutter.
 */
@SuppressLint("MissingPermission")
class BluetoothSerialManager(
    private val callbackChannel: BluetoothSerialCallbackChannel,
) : BluetoothSerialPlatformChannel {

    private class Connection(
        val socket: BluetoothSocket,
        val readThread: Thread,
    )

    private val connections = mutableMapOf<String, Connection>()

    override fun connect(
        deviceId: String,
        serviceUuid: String,
        callback: (Result<Unit>) -> Unit,
    ) {
        synchronized(connections) {
            if (connections.containsKey(deviceId)) {
                Log.d(SERIAL_TAG, "Already connected to $deviceId")
                onConnected(deviceId)
                callback(Result.success(Unit))
                return
            }
        }

        val adapter = bluetoothAdapter
        if (adapter == null) {
            callback(Result.failure(FlutterError("Failed", "Bluetooth adapter not available")))
            return
        }

        Thread {
            val device: BluetoothDevice = try {
                getBluetoothDeviceFromId(deviceId)
            } catch (e: Exception) {
                postResult(callback, Result.failure(FlutterError("NotFound", e.toString())))
                return@Thread
            }

            // Discovery interferes with an RFCOMM connect request.
            try {
                adapter.cancelDiscovery()
            } catch (e: Exception) {
                Log.d(SERIAL_TAG, "cancelDiscovery failed: ${e.message}")
            }

            val socket: BluetoothSocket = try {
                openSocket(device, UUID.fromString(serviceUuid))
            } catch (e: Exception) {
                postResult(callback, Result.failure(FlutterError("Failed", e.toString())))
                return@Thread
            }

            val readThread = Thread { readLoop(deviceId, socket) }
            synchronized(connections) {
                connections[deviceId] = Connection(socket, readThread)
            }
            onConnected(deviceId)
            postResult(callback, Result.success(Unit))
            readThread.start()
        }.start()
    }

    override fun disconnect(deviceId: String, callback: (Result<Unit>) -> Unit) {
        closeConnection(deviceId, notify = true)
        callback(Result.success(Unit))
    }

    override fun send(deviceId: String, data: ByteArray) {
        val connection = synchronized(connections) { connections[deviceId] }
            ?: throw FlutterError("NotFound", "Device not connected")
        try {
            connection.socket.outputStream.write(data)
            connection.socket.outputStream.flush()
        } catch (e: IOException) {
            throw FlutterError("Failed", "Failed to send data: ${e.message}")
        }
    }

    /** Closes every open connection, e.g. when the engine detaches. */
    fun dispose() {
        val deviceIds = synchronized(connections) { connections.keys.toList() }
        for (deviceId in deviceIds) {
            closeConnection(deviceId, notify = false)
        }
    }

    /**
     * Tries the secure RFCOMM socket first and falls back to the insecure one,
     * which is what unauthenticated serial modules require.
     */
    private fun openSocket(device: BluetoothDevice, uuid: UUID): BluetoothSocket {
        val secure = device.createRfcommSocketToServiceRecord(uuid)
        try {
            secure.connect()
            return secure
        } catch (e: IOException) {
            Log.d(SERIAL_TAG, "Secure RFCOMM connect failed, retrying insecure: ${e.message}")
            try {
                secure.close()
            } catch (_: IOException) {
            }
        }

        val insecure = device.createInsecureRfcommSocketToServiceRecord(uuid)
        try {
            insecure.connect()
            return insecure
        } catch (e: IOException) {
            try {
                insecure.close()
            } catch (_: IOException) {
            }
            throw e
        }
    }

    private fun readLoop(deviceId: String, socket: BluetoothSocket) {
        val buffer = ByteArray(1024)
        try {
            val input = socket.inputStream
            while (true) {
                val read = input.read(buffer)
                if (read <= 0) break
                val data = buffer.copyOf(read)
                postToMain { callbackChannel.onData(deviceId, data) {} }
            }
        } catch (e: IOException) {
            Log.d(SERIAL_TAG, "Read loop ended for $deviceId: ${e.message}")
        } finally {
            closeConnection(deviceId, notify = true)
        }
    }

    /** Returns whether a connection was open. */
    private fun closeConnection(deviceId: String, notify: Boolean): Boolean {
        val connection = synchronized(connections) { connections.remove(deviceId) }
            ?: return false
        try {
            connection.socket.close()
        } catch (e: IOException) {
            Log.d(SERIAL_TAG, "Failed to close socket for $deviceId: ${e.message}")
        }
        connection.readThread.interrupt()
        if (notify) onDisconnected(deviceId)
        return true
    }

    private fun onConnected(deviceId: String) {
        postToMain { callbackChannel.onConnectionStateChanged(deviceId, true) {} }
    }

    private fun onDisconnected(deviceId: String) {
        postToMain { callbackChannel.onConnectionStateChanged(deviceId, false) {} }
    }

    private fun postToMain(block: () -> Unit) {
        val handler = accessoryManagerThreadHandler
        if (handler != null) {
            handler.post(block)
        } else {
            block()
        }
    }

    private fun postResult(callback: (Result<Unit>) -> Unit, result: Result<Unit>) {
        postToMain { callback(result) }
    }
}
