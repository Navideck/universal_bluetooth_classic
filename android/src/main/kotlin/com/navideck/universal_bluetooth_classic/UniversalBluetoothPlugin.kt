package com.navideck.universal_bluetooth_classic

import android.annotation.SuppressLint
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothDevice.BOND_BONDED
import android.bluetooth.BluetoothManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Context.RECEIVER_EXPORTED
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import kotlinx.coroutines.CompletableDeferred

private const val TAG = "UniversalBluetoothPlugin"

@SuppressLint("MissingPermission")
class UniversalBluetoothPlugin : FlutterAccessoryPlatformChannel, FlutterPlugin,
    ActivityAware {
    private var callbackChannel: FlutterAccessoryCallbackChannel? = null
    private var serialManager: BluetoothSerialManager? = null
    private val pairResultFutures = mutableMapOf<String, CompletableDeferred<Boolean>>()
    private var activity: Activity? = null
    private val actionBluetoothSelected =
        "android.bluetooth.devicepicker.action.DEVICE_SELECTED"

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        accessoryManagerThreadHandler = Handler(Looper.getMainLooper())
        val context = flutterPluginBinding.applicationContext

        val bluetoothManager =
            context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?
        bluetoothAdapter = bluetoothManager?.adapter

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P && bluetoothAdapter != null) {
            val bluetoothHidManager = BluetoothHidManager(
                context,
                BluetoothHidManagerCallbackChannel(flutterPluginBinding.binaryMessenger)
            )
            BluetoothHidManagerPlatformChannel.setUp(
                flutterPluginBinding.binaryMessenger,
                bluetoothHidManager,
            )
            AndroidSdpChannel.setUp(
                flutterPluginBinding.binaryMessenger,
                bluetoothHidManager,
            )
        } else {
            Log.e(TAG, "BluetoothHidManager not initialized")
        }

        callbackChannel = FlutterAccessoryCallbackChannel(flutterPluginBinding.binaryMessenger)
        FlutterAccessoryPlatformChannel.setUp(flutterPluginBinding.binaryMessenger, this)

        val serial = BluetoothSerialManager(
            BluetoothSerialCallbackChannel(flutterPluginBinding.binaryMessenger)
        )
        serialManager = serial
        BluetoothSerialPlatformChannel.setUp(flutterPluginBinding.binaryMessenger, serial)


        val intentFilter = IntentFilter(BluetoothDevice.ACTION_FOUND)
        intentFilter.addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(broadcastReceiver, intentFilter, RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(broadcastReceiver, intentFilter)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        accessoryManagerThreadHandler = null
        callbackChannel = null
        bluetoothAdapter = null
        serialManager?.dispose()
        serialManager = null
        binding.applicationContext.unregisterReceiver(broadcastReceiver)
    }


    override suspend fun showBluetoothAccessoryPicker(withNames: List<String>) {
        try {
            activity?.registerReceiver(broadcastReceiver, IntentFilter(actionBluetoothSelected))
            val bluetoothPicker = Intent("android.bluetooth.devicepicker.action.LAUNCH")
            activity?.startActivity(bluetoothPicker)
        } catch (e: Exception) {
            throw FlutterError("Failed", e.toString())
        }
    }

    override fun startScan() {
        val adapter = bluetoothAdapter ?: return

        if (!adapter.isEnabled) {
            throw FlutterError("AdapterDisabled", "Bluetooth Adapter is disabled")
        }

        if (adapter.isDiscovering) {
            Log.d(TAG, "Already Discovering")
            return
        }

        if (!adapter.startDiscovery()) {
            throw FlutterError("failed", "Failed to start discovery")
        }

    }

    override fun stopScan() {
        val adapter = bluetoothAdapter ?: return

        if (!adapter.isEnabled) {
            throw FlutterError("AdapterDisabled", "Bluetooth Adapter is disabled")
        }

        if (!adapter.isDiscovering) {
            Log.d(TAG, "Already not discovering")
            return
        }

        if (!adapter.cancelDiscovery()) {
            throw FlutterError("failed", "Failed to cancel discovery")
        }
    }

    override fun isScanning(): Boolean {
        return bluetoothAdapter?.isDiscovering ?: false
    }

    override fun getPairedDevices(): List<com.navideck.universal_bluetooth_classic.BluetoothDevice> {
        return bluetoothAdapter?.bondedDevices?.filter { it.type != BluetoothDevice.DEVICE_TYPE_LE }
            ?.map { it.toFlutter(null) } ?: listOf()
    }

    override suspend fun pair(address: String): Boolean {
        val remoteDevice = try {
            getBluetoothDeviceFromId(address)
        } catch (e: Exception) {
            throw FlutterError("Failed", e.toString(), null)
        }

        // If already paired, return and complete pending futures
        if (remoteDevice.bondState == BOND_BONDED) {
            pairResultFutures.remove(address)?.complete(true)
            return true
        }

        // throw error if we already have a pending future
        if (pairResultFutures.containsKey(address)) {
            throw FlutterError("InProgress", "Pairing already in progress", null)
        }

        // Make a Pair request and complete future from Pair Update intent
        if (!remoteDevice.createBond()) {
            throw FlutterError("Failed", "Failed to pair", null)
        }

        val future = CompletableDeferred<Boolean>()
        pairResultFutures[address] = future
        return future.await()
    }

    override suspend fun unpair(address: String) {
        try {
            val remoteDevice = getBluetoothDeviceFromId(address)
            if (remoteDevice.bondState == BOND_BONDED) {
                remoteDevice.javaClass.getMethod("removeBond").invoke(remoteDevice)
            }
        } catch (e: Exception) {
            throw FlutterError("Failed", e.toString())
        }
    }

    private fun onBondStateUpdate(deviceId: String, bonded: Boolean, error: String? = null) {
        pairResultFutures.remove(deviceId)?.complete(bonded)
    }

    private fun onBluetoothDeviceSelectFromPicker(device: BluetoothDevice) {
        Log.d(TAG, "Selected device: ${device.name} ${device.address}")
        if (device.bondState == BOND_BONDED) {
            Log.d(TAG, "${device.name} already paired")
            return
        }
        // Create bond to selected device
        device.createBond()
    }

    private val broadcastReceiver: BroadcastReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val device: BluetoothDevice? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(
                        BluetoothDevice.EXTRA_DEVICE,
                        BluetoothDevice::class.java
                    )
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                }

            if (device == null) return

            when (intent.action) {
                actionBluetoothSelected -> {
                    onBluetoothDeviceSelectFromPicker(device)
                }

                BluetoothDevice.ACTION_FOUND -> {
                    if (device.type == BluetoothDevice.DEVICE_TYPE_LE) return
                    val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE)
                    // Cache the result
                    postCallback {
                        callbackChannel?.onDeviceDiscover(deviceArg = device.toFlutter(rssi.toLong()))
                    }
                }

                BluetoothDevice.ACTION_BOND_STATE_CHANGED -> {
                    when (intent.getIntExtra(
                        BluetoothDevice.EXTRA_BOND_STATE,
                        BluetoothDevice.ERROR
                    )) {
                        BluetoothDevice.BOND_BONDING -> {
                            Log.v(TAG, "${device.address} BOND_BONDING")
                        }

                        BluetoothDevice.BOND_BONDED -> {
                            onBondStateUpdate(device.address, true)
                        }

                        BluetoothDevice.ERROR -> {
                            onBondStateUpdate(device.address, false, "Failed to Pair")
                        }

                        BluetoothDevice.BOND_NONE -> {
                            Log.e(TAG, "${device.address} BOND_NONE")
                            onBondStateUpdate(device.address, false)
                        }
                    }
                }
            }
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onDetachedFromActivityForConfigChanges() {}
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}


}
