import java.util.Properties
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val isReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("Release", ignoreCase = true)
}
val releaseStoreFile = keystoreProperties["storeFile"]?.toString().orEmpty()
val releaseKeyAlias = keystoreProperties["keyAlias"]?.toString().orEmpty()
val usesAndroidDebugCertificate =
    releaseStoreFile.replace('\\', '/').endsWith("/.android/debug.keystore") ||
        releaseKeyAlias == "androiddebugkey"
val allowDebugReleaseSigning =
    providers.gradleProperty("allowDebugReleaseSigning").orNull == "true" ||
        System.getenv("SAJIA_ALLOW_DEBUG_RELEASE_SIGNING") == "true"
if (isReleaseBuild && !keystorePropertiesFile.exists()) {
    throw GradleException(
        "Release signing belum siap: key.properties tidak ditemukan. " +
            "Jalankan scripts/create_upload_keystore.ps1 lalu isi key.properties."
    )
}
if (isReleaseBuild && usesAndroidDebugCertificate && !allowDebugReleaseSigning) {
    throw GradleException(
        "Release production ditolak: key.properties masih memakai Android Debug certificate. " +
            "Gunakan upload keystore permanen. Untuk APK beta internal saja, " +
            "set -PallowDebugReleaseSigning=true secara eksplisit."
    )
}

android {
    namespace = "id.aksaldev.sajia"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "id.aksaldev.sajia"
        // Android 8.0 (API 26) and newer. The public release contains both
        // 32-bit ARM and 64-bit ARM native libraries for older tablets.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.android.play:integrity:1.4.0")
}
