# Keep Flutter plugin registrant and generated entry points.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Supabase/HTTP JSON payloads are reflection-light, but keeping Kotlin metadata
# prevents aggressive minification from breaking plugin/service discovery.
-keep class kotlin.Metadata { *; }

# WebView payment flow.
-keep class * extends android.webkit.WebViewClient { *; }
-keep class * extends android.webkit.WebChromeClient { *; }

# Bluetooth printer plugin may use platform callbacks from native code.
-keep class com.gprinter.** { *; }
-keep class id.aksaldev.sajia.** { *; }

# Flutter references Play Core deferred-components classes even when the app
# does not use deferred components. Do not ship Play Core just to satisfy R8.
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task
