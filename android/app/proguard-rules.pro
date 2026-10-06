# Flutter Core
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# Java 8+ Desugaring
-keep class java.time.** { *; }

# Networking & WebSockets
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# Sarvam SDK & Audio
-keep class com.sarvam.** { *; }
-dontwarn com.sarvam.**
-keep class com.sarvam_ai.** { *; }
-dontwarn com.sarvam_ai.**
-keep class ai.sarvam.** { *; }
-dontwarn ai.sarvam.**

# Play Core deferred components optional references
-dontwarn com.google.android.play.core.**

# Keep annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
