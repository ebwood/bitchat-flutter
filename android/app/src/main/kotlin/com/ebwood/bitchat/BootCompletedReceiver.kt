package com.ebwood.bitchat

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Boot completed receiver — auto-starts mesh service on device boot.
///
/// Matches Android BootCompletedReceiver.kt from original bitchat.
class BootCompletedReceiver : BroadcastReceiver() {

    companion object {
        private const val PREF_NAME = "bitchat_boot"
        private const val KEY_ENABLED = "auto_start_enabled"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            if (prefs.getBoolean(KEY_ENABLED, false)) {
                // Start the mesh foreground service
                val serviceIntent = Intent(context, MeshForegroundService::class.java).apply {
                    putExtra("title", "BitChat Mesh")
                    putExtra("body", "Auto-started on boot")
                }
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                    context.startForegroundService(serviceIntent)
                } else {
                    context.startService(serviceIntent)
                }
            }
        }
    }
}

/// Flutter plugin for boot receiver control.
class BootReceiverPlugin(
    private val context: Context,
    private val channel: MethodChannel
) : MethodChannel.MethodCallHandler {

    companion object {
        private const val PREF_NAME = "bitchat_boot"
        private const val KEY_ENABLED = "auto_start_enabled"
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isEnabled" -> {
                val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                result.success(prefs.getBoolean(KEY_ENABLED, false))
            }

            "setEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val prefs = context.getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
                prefs.edit().putBoolean(KEY_ENABLED, enabled).apply()

                // Enable/disable the receiver component
                val componentName = ComponentName(context, BootCompletedReceiver::class.java)
                val newState = if (enabled) {
                    PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                } else {
                    PackageManager.COMPONENT_ENABLED_STATE_DISABLED
                }
                context.packageManager.setComponentEnabledSetting(
                    componentName,
                    newState,
                    PackageManager.DONT_KILL_APP
                )

                result.success(enabled)
            }

            else -> result.notImplemented()
        }
    }
}
