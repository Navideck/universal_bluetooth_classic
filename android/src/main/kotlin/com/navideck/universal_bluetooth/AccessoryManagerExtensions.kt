package com.navideck.universal_bluetooth

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothHidDevice
import android.bluetooth.BluetoothProfile
import android.os.Build
import android.os.Handler

// Public reusable variables
internal var accessoryManagerThreadHandler: Handler? = null
internal var btHidProxy: BluetoothHidDevice? = null
internal var bluetoothAdapter: BluetoothAdapter? = null

@SuppressLint("MissingPermission")
internal fun BluetoothDevice.toFlutter(rssi: Long?): com.navideck.universal_bluetooth.BluetoothDevice {
    return BluetoothDevice(
        address = this.address,
        name = this.name,
        rssi = rssi ?: 0,
        paired = this.bondState == BluetoothDevice.BOND_BONDED,
        deviceClass = this.bluetoothClass.majorDeviceClass.toDeviceClass(),
        deviceType = this.type.toDeviceType(),
        isConnectedWithHid = this.isConnectedWithHID(),
    )
}

@SuppressLint("MissingPermission")
internal fun getBluetoothDeviceFromId(deviceId: String): BluetoothDevice {
    return bluetoothAdapter?.getRemoteDevice(deviceId)
        ?: throw Exception("Device not found, please scan")
}


internal fun Int.toDeviceType(): DeviceType? {
    return when (this) {
        BluetoothDevice.DEVICE_TYPE_CLASSIC -> DeviceType.CLASSIC
        BluetoothDevice.DEVICE_TYPE_LE -> DeviceType.LE
        BluetoothDevice.DEVICE_TYPE_DUAL -> DeviceType.DUAL
        BluetoothDevice.DEVICE_TYPE_UNKNOWN -> DeviceType.UNKNOWN
        else -> null
    }
}

internal fun Int.toDeviceClass(): DeviceClass? {
    return when (this) {
        BluetoothClass.Device.Major.AUDIO_VIDEO -> DeviceClass.AUDIO_VIDEO
        BluetoothClass.Device.Major.COMPUTER -> DeviceClass.COMPUTER
        BluetoothClass.Device.Major.HEALTH -> DeviceClass.HEALTH
        BluetoothClass.Device.Major.IMAGING -> DeviceClass.IMAGING
        BluetoothClass.Device.Major.MISC -> DeviceClass.MISC
        BluetoothClass.Device.Major.NETWORKING -> DeviceClass.NETWORKING
        BluetoothClass.Device.Major.PERIPHERAL -> DeviceClass.PERIPHERAL
        BluetoothClass.Device.Major.PHONE -> DeviceClass.PHONE
        BluetoothClass.Device.Major.UNCATEGORIZED -> DeviceClass.UNCATEGORIZED
        BluetoothClass.Device.Major.WEARABLE -> DeviceClass.WEARABLE
        else -> null
    }
}


@SuppressLint("MissingPermission")
private fun BluetoothDevice.isConnectedWithHID(): Boolean? {
    return btHidProxy?.let {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            it.getConnectionState(this) == BluetoothProfile.STATE_CONNECTED
        } else {
            null
        }
    }
}