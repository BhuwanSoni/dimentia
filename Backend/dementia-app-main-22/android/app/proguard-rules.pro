# Keep flutter_local_notifications classes from being stripped by R8/ProGuard
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Keep NotificationCompat used internally by the plugin
-keep class androidx.core.app.NotificationCompat { *; }
-keep class androidx.core.app.NotificationCompat$* { *; }

# Keep Gson (used by flutter_local_notifications for serialising scheduled data)
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Keep Firebase Messaging
-keep class com.google.firebase.messaging.** { *; }