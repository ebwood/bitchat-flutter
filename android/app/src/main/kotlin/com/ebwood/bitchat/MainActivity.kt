package com.ebwood.bitchat

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // Register BLE Peripheral plugin
        BLEPeripheralPlugin(
            context = this,
            channel = MethodChannel(messenger, "com.ebwood.bitchat/ble_peripheral")
        )

        // Register Foreground Service plugin
        ForegroundServicePlugin(
            context = this,
            channel = MethodChannel(messenger, "com.ebwood.bitchat/foreground_service")
        )

        // Register Boot Receiver plugin
        BootReceiverPlugin(
            context = this,
            channel = MethodChannel(messenger, "com.ebwood.bitchat/boot_receiver")
        )
    }
}
