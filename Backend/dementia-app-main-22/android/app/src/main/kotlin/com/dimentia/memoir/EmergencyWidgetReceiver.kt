package com.dimentia.memoir

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class EmergencyWidgetReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_EMERGENCY_TAP = "com.dimentia.memoir.EMERGENCY_TAP"

        // ✅ MUST match the key used when Flutter saves to SharedPreferences
        const val PREFS_NAME = "FlutterSharedPreferences"
        const val KEY_PHONE  = "flutter.emergency_contact"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_EMERGENCY_TAP) return

        // Read phone number saved by Flutter via SharedPreferences
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val phoneNumber = prefs.getString(KEY_PHONE, "") ?: ""

        val activityIntent = Intent(context, EmergencyActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("phoneNumber", phoneNumber)
        }
        context.startActivity(activityIntent)
    }
}