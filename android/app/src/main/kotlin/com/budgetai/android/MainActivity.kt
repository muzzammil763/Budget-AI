package com.budgetai.android

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.widget.Toast
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : FlutterFragmentActivity() {
    private val backgroundChatChannel = "budget_ai/background_chat"
    private val appActionChannelName = "budget_ai/android_app_action"
    private var appActionChannel: MethodChannel? = null
    private var textToSpeech: TextToSpeech? = null
    private var pendingSpeech: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            backgroundChatChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val title = call.argument<String>("title") ?: "Budget AI chat running"
                    val text = call.argument<String>("text")
                        ?: "Keeping the active chat response connected."
                    try {
                        BackgroundChatService.start(this, title, text)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("BACKGROUND_CHAT_START_ERROR", e.message, null)
                    }
                }
                "stop" -> {
                    BackgroundChatService.stop(this)
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

        appActionChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            appActionChannelName,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialAction" -> result.success(takeFinanceAction(intent))
                    "speakConfirmation" -> {
                        val message = call.argument<String>("message").orEmpty()
                        if (message.isNotBlank()) speakConfirmation(message)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeFinanceAction(intent)?.let { uri ->
            appActionChannel?.invokeMethod("financeAction", uri)
        }
    }

    private fun takeFinanceAction(source: Intent?): String? {
        val uri = source?.data ?: return null
        if (uri.scheme != "budgetai" || uri.host != "finance") return null
        source.data = null
        return uri.toString()
    }

    private fun speakConfirmation(message: String) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show()
        val current = textToSpeech
        if (current != null) {
            current.speak(message, TextToSpeech.QUEUE_FLUSH, null, "budget_ai_confirmation")
            return
        }

        pendingSpeech = message
        textToSpeech = TextToSpeech(applicationContext) { status ->
            if (status == TextToSpeech.SUCCESS) {
                textToSpeech?.language = Locale.getDefault()
                pendingSpeech?.let { text ->
                    textToSpeech?.speak(
                        text,
                        TextToSpeech.QUEUE_FLUSH,
                        null,
                        "budget_ai_confirmation",
                    )
                }
            }
            pendingSpeech = null
        }
    }

    override fun onDestroy() {
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        super.onDestroy()
    }

    private fun isBatteryOptimizationIgnored(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val powerManager = getSystemService(POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(packageName)
    }
}
