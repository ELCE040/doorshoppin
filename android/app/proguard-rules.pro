# Flutter / Dart
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Google Play Services / Firebase
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Play Core (optional; Flutter references it for deferred components – we don't use it)
-dontwarn com.google.android.play.core.**

# Keep R for resource access
-keepclassmembers class **.R$* { public static <fields>; }
