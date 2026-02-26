package com.ebwood.bitchat

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.os.ParcelUuid
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/// BLE Peripheral plugin — exposes BluetoothLeAdvertiser to Flutter.
///
/// Handles GATT server, advertising, and data exchange with centrals.
class BLEPeripheralPlugin(
    private val context: Context,
    private val channel: MethodChannel
) : MethodChannel.MethodCallHandler {

    companion object {
        val SERVICE_UUID: UUID = UUID.fromString("F47B5E2D-4A9E-4C5A-9B3F-8E1D2C3A4B5C")
        val CHARACTERISTIC_UUID: UUID = UUID.fromString("A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D")
    }

    private var bluetoothManager: BluetoothManager? = null
    private var gattServer: BluetoothGattServer? = null
    private var characteristic: BluetoothGattCharacteristic? = null
    private val connectedDevices = mutableListOf<BluetoothDevice>()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> {
                bluetoothManager = context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
                if (bluetoothManager?.adapter?.isEnabled == true) {
                    setupGattServer()
                    result.success("idle")
                } else {
                    result.success("unknown")
                }
            }

            "startAdvertising" -> {
                val serviceUUID = call.argument<String>("serviceUUID")
                    ?: return result.error("INVALID_ARGS", "Missing serviceUUID", null)

                val uuid = UUID.fromString(serviceUUID)
                startAdvertising(uuid)
                result.success(true)
            }

            "stopAdvertising" -> {
                stopAdvertising()
                result.success(null)
            }

            "sendData" -> {
                val data = call.argument<ByteArray>("data")
                if (data != null && characteristic != null) {
                    characteristic!!.value = data
                    connectedDevices.forEach { device ->
                        gattServer?.notifyCharacteristicChanged(device, characteristic!!, false)
                    }
                    result.success(true)
                } else {
                    result.success(false)
                }
            }

            "getConnectedCount" -> {
                result.success(connectedDevices.size)
            }

            else -> result.notImplemented()
        }
    }

    private fun setupGattServer() {
        gattServer = bluetoothManager?.openGattServer(context, gattCallback)

        characteristic = BluetoothGattCharacteristic(
            CHARACTERISTIC_UUID,
            BluetoothGattCharacteristic.PROPERTY_READ or
                    BluetoothGattCharacteristic.PROPERTY_WRITE or
                    BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE or
                    BluetoothGattCharacteristic.PROPERTY_NOTIFY,
            BluetoothGattCharacteristic.PERMISSION_READ or
                    BluetoothGattCharacteristic.PERMISSION_WRITE
        )

        val service = BluetoothGattService(
            SERVICE_UUID,
            BluetoothGattService.SERVICE_TYPE_PRIMARY
        )
        service.addCharacteristic(characteristic!!)
        gattServer?.addService(service)
    }

    private fun startAdvertising(serviceUUID: UUID) {
        val advertiser = bluetoothManager?.adapter?.bluetoothLeAdvertiser ?: return

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTimeout(0) // Advertise indefinitely
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .addServiceUuid(ParcelUuid(serviceUUID))
            .build()

        advertiser.startAdvertising(settings, data, advertiseCallback)
    }

    private fun stopAdvertising() {
        bluetoothManager?.adapter?.bluetoothLeAdvertiser?.stopAdvertising(advertiseCallback)
        gattServer?.close()
        connectedDevices.clear()
    }

    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
            channel.invokeMethod("onStateChanged", "advertising")
        }

        override fun onStartFailure(errorCode: Int) {
            channel.invokeMethod("onStateChanged", "error")
        }
    }

    private val gattCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothGatt.STATE_CONNECTED) {
                connectedDevices.add(device)
                channel.invokeMethod("onCentralConnected", device.address)
            } else if (newState == BluetoothGatt.STATE_DISCONNECTED) {
                connectedDevices.remove(device)
                channel.invokeMethod("onCentralDisconnected", device.address)
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray?
        ) {
            if (value != null) {
                channel.invokeMethod("onDataReceived", mapOf(
                    "data" to value.toList(),
                    "centralId" to device.address
                ))
            }
            if (responseNeeded) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
            }
        }
    }
}
