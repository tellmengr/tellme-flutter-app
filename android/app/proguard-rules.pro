# --- Firebase / Google Play Services (what you already had)
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# --- Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# --- Play Core (fixes the "Missing class com.google.android.play.core.*" R8 errors)
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.splitinstall.** { *; }
-keep class com.google.android.play.core.tasks.** { *; }
-keep class com.google.android.play.core.splitcompat.** { *; }

# (Optional but harmless) Keep Flutter deferred components glue
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }

# Keep some metadata so annotations and inner classes survive shrinking
-keepattributes *Annotation*,InnerClasses,EnclosingMethod
