package com.navideck.universal_bluetooth_classic

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.util.Log
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import kotlinx.coroutines.CompletableDeferred

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

    /**
     * Device IDs with a connect in flight. The socket is opened on a background
     * thread and only recorded in [connections] once it is up, so this flag
     * stops a second overlapping connect from opening (and later leaking) a
     * second socket for the same device.
     */
    private val connecting = mutableSetOf<String>()

    /**
     * Socket writes block until the peer accepts the bytes, so they are kept off
     * the platform thread. A single worker also keeps the bytes of concurrent
     * sends in order.
     */
    private val writeExecutor = Executors.newSingleThreadExecutor()

    override suspend fun connect(deviceId: String, serviceUuid: String) {
        synchronized(connections) {
            if (connections.containsKey(deviceId)) {
                Log.d(SERIAL_TAG, "Already connected to $deviceId")
                onConnected(deviceId)
                return
            }
            if (!connecting.add(deviceId)) {
                throw FlutterError(
                    "InProgress",
                    "A connection to $deviceId is already in progress"
                )
            }
        }

        val adapter = bluetoothAdapter
        if (adapter == null) {
            synchronized(connections) { connecting.remove(deviceId) }
            throw FlutterError("Failed", "Bluetooth adapter not available")
        }

        val result = CompletableDeferred<Unit>()
        Thread {
            try {
                val device: BluetoothDevice = try {
                    getBluetoothDeviceFromId(deviceId)
                } catch (e: Exception) {
                    result.completeExceptionally(FlutterError("NotFound", e.toString()))
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
                    result.completeExceptionally(FlutterError("Failed", e.toString()))
                    return@Thread
                }

                val readThread = Thread { readLoop(deviceId, socket) }
                synchronized(connections) {
                    connections[deviceId] = Connection(socket, readThread)
                }
                onConnected(deviceId)
                result.complete(Unit)
                readThread.start()
            } finally {
                // The connect is no longer pending, whether it succeeded or not.
                synchronized(connections) { connecting.remove(deviceId) }
            }
        }.start()

        result.await()
    }

    override suspend fun disconnect(deviceId: String) {
        closeConnection(deviceId, notify = true)
    }

    override suspend fun send(deviceId: String, data: ByteArray) {
        val connection = synchronized(connections) { connections[deviceId] }
            ?: throw FlutterError("NotFound", "Device not connected")

        val result = CompletableDeferred<Unit>()
        try {
            writeExecutor.execute {
                try {
                    connection.socket.outputStream.write(data)
                    connection.socket.outputStream.flush()
                    result.complete(Unit)
                } catch (e: IOException) {
                    result.completeExceptionally(
                        FlutterError("Failed", "Failed to send data: ${e.message}")
                    )
                }
            }
        } catch (e: RejectedExecutionException) {
            throw FlutterError("Failed", "Serial manager disposed")
        }
        result.await()
    }

    /** Closes every open connection, e.g. when the engine detaches. */
    fun dispose() {
        writeExecutor.shutdown()
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
                postCallback { callbackChannel.onData(deviceId, data) }
            }
        } catch (e: IOException) {
            Log.d(SERIAL_TAG, "Read loop ended for $deviceId: ${e.message}")
        } finally {
            // Only tear down the connection this read loop belongs to. A fast
            // disconnect-then-reconnect could otherwise close the new socket.
            closeConnection(deviceId, notify = true, socket = socket)
        }
    }

    /**
     * Closes the connection for [deviceId] and returns whether one was open.
     *
     * When [socket] is given the connection is only closed if it is still backed
     * by that socket, so a stale read loop cannot tear down a newer connection.
     */
    private fun closeConnection(
        deviceId: String,
        notify: Boolean,
        socket: BluetoothSocket? = null,
    ): Boolean {
        val connection = synchronized(connections) {
            val current = connections[deviceId] ?: return false
            if (socket != null && current.socket !== socket) return false
            connections.remove(deviceId)
            current
        }
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
        postCallback { callbackChannel.onConnectionStateChanged(deviceId, true) }
    }

    private fun onDisconnected(deviceId: String) {
        postCallback { callbackChannel.onConnectionStateChanged(deviceId, false) }
    }
}
