package com.dimentia.memoir
 
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import androidx.activity.OnBackPressedCallback
import io.flutter.embedding.android.FlutterActivity
 

class EmergencyActivity : FlutterActivity() {
 
    private var phoneNumber: String = ""
 
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
 
        // ✅ Play Store safe lock screen API
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
 
        setContentView(R.layout.activity_emergency)
 
        // ✅ Read phone number from Flutter — handle blank safely
        phoneNumber = intent.getStringExtra("phoneNumber")
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: ""
 
        // ✅ Vibrate on open — alerts the user something urgent happened
        vibrateDevice()
 
        val tvSubtitle = findViewById<TextView>(R.id.tvSubtitle)
        val tvNumber   = findViewById<TextView>(R.id.tvPhoneNumber)
        val callBtn    = findViewById<Button>(R.id.callButton)
        val cancelBtn  = findViewById<Button>(R.id.cancelButton)
 
        // ✅ Dynamic subtitle + safe empty number handling
        if (phoneNumber.isBlank()) {
            tvSubtitle.text   = "No emergency contact found"
            tvNumber.text     = "⚠️ Please add a number in Settings"
            callBtn.isEnabled = false
            callBtn.alpha     = 0.4f
        } else {
            tvSubtitle.text = "Tap below to call for help"
            tvNumber.text   = "📞 $phoneNumber"
        }
 
        // ✅ ACTION_DIAL — Play Store safe, user confirms the call
        callBtn.setOnClickListener {
            val intent = Intent(Intent.ACTION_DIAL).apply {
                data = Uri.parse("tel:$phoneNumber")
            }
            startActivity(intent)
            // ✅ Slight delay before finish — smoother exit UX
            callBtn.postDelayed({ finish() }, 300)
        }
 
        cancelBtn.setOnClickListener { finish() }
    }

    // ✅ Modern back press — replaces deprecated onBackPressed()
    override fun onBackPressed() {
        finish()
    }
 
    // ✅ Handles all Android versions correctly (S+, O+, legacy)
    private fun vibrateDevice() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val manager = getSystemService(VibratorManager::class.java)
                manager?.defaultVibrator?.vibrate(
                    VibrationEffect.createOneShot(250, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Vibrator::class.java)
                vibrator?.vibrate(
                    VibrationEffect.createOneShot(250, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                @Suppress("DEPRECATION")
                val vibrator = getSystemService(Vibrator::class.java)
                @Suppress("DEPRECATION")
                vibrator?.vibrate(250)
            }
        } catch (e: Exception) {
            // Vibration is non-critical — silently ignore
        }
    }
}
