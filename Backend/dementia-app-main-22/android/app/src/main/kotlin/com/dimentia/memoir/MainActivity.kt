package com.dimentia.memoir

import android.content.Intent
import android.os.Bundle
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    // ✅ MUST match Flutter side exactly
    private val CHANNEL = "emergency_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ✅ Create notification channel (required for Android 8+)
        createNotificationChannel()

        // ✅ Connect MethodChannel to Flutter
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startEmergency" -> {
                    try {
                        // ✅ Read caregiver number passed from Flutter
                        val phoneNumber = call.argument<String>("phoneNumber")
                            ?: "1234567890" // fallback

                        val intent = Intent(this, EmergencyActivity::class.java).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            putExtra("phoneNumber", phoneNumber)
                        }
                        startActivity(intent)
                        result.success("Emergency started")
                    } catch (e: Exception) {
                        result.error("EMERGENCY_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "emergency_channel",
                "Emergency Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Used for emergency caregiver alerts"
                enableLights(true)
                enableVibration(true)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }
}