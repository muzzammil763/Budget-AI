package com.budgetai.android

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    private val installChannel = "open_gate/install_apk"
    private val backgroundAgentChannel = "open_gate/background_agent"
    private val TAG = "OpenGateInstall"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            installChannel,
        ).setMethodCallHandler { call, result ->
            if (call.method == "installApk") {
                val filePath = call.argument<String>("path")
                if (filePath == null) {
                    result.error("INVALID_ARG", "path is null", null)
                    return@setMethodCallHandler
                }
                try {
                    val file = File(filePath)
                    if (!file.exists()) {
                        result.error("FILE_NOT_FOUND", "APK file does not exist: $filePath", null)
                        return@setMethodCallHandler
                    }
                    if (!file.canRead()) {
                        result.error("FILE_NOT_READABLE", "APK file is not readable: $filePath", null)
                        return@setMethodCallHandler
                    }
                    Log.d(TAG, "Installing APK from: ${file.absolutePath}, size: ${file.length()}")

                    val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        FileProvider.getUriForFile(
                            this,
                            "${applicationContext.packageName}.fileprovider",
                            file,
                        )
                    } else {
                        Uri.fromFile(file)
                    }
                    Log.d(TAG, "APK content URI: $uri")

                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
                    }

                    // Grant read permission to the system package installer explicitly
                    val installerPackage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        packageManager.getInstallSourceInfo(packageName).initiatingPackageName
                    } else {
                        null
                    }
                    if (installerPackage != null) {
                        grantUriPermission(installerPackage, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        Log.d(TAG, "Granted URI permission to: $installerPackage")
                    }

                    // Check if any activity can handle this intent
                    if (intent.resolveActivity(packageManager) == null) {
                        result.error("NO_INSTALLER", "No app found to handle APK installation", null)
                        return@setMethodCallHandler
                    }

                    startActivity(intent)
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "Install error", e)
                    result.error("INSTALL_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            backgroundAgentChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title") ?: "Budget AI agent running"
                    val text = call.argument<String>("text")
                        ?: "Keeping the active agent response connected."
                    try {
                        BackgroundAgentService.start(this, title, text)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BACKGROUND_AGENT_START_ERROR", e.message, null)
                    }
                }
                "stop" -> {
                    BackgroundAgentService.stop(this)
                    result.success(true)
                }
                "isBatteryOptimizationIgnored" -> {
                    result.success(isBatteryOptimizationIgnored())
                }
                "requestBatteryOptimizationExemption" -> {
                    try {
                        if (!isBatteryOptimizationIgnored()) {
                            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BATTERY_SETTINGS_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }
}
