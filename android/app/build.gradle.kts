import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.camera.camera_handheld"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.camera.camera_handheld"
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Production-ready signing: if a key.properties file exists at the project
    // root (committed via CI secrets), use a real release keystore. Otherwise
    // fall back to the debug key so local `flutter build apk --release` still works.
    val keystorePropertiesFile = rootProject.file("key.properties")
    val hasReleaseKey = keystorePropertiesFile.exists()
    if (hasReleaseKey) {
        val keystoreProperties = Properties()
        keystoreProperties.load(keystorePropertiesFile.inputStream())
        signingConfigs {
            create("release") {
                keyAlias =
                    keystoreProperties.getProperty("keyAlias")
                        ?: error("key.properties 缺少 keyAlias")
                keyPassword =
                    keystoreProperties.getProperty("keyPassword")
                        ?: error("key.properties 缺少 keyPassword")
                val storeFilePath =
                    keystoreProperties.getProperty("storeFile")
                        ?: error("key.properties 缺少 storeFile")
                storeFile = file(storeFilePath)
                storePassword =
                    keystoreProperties.getProperty("storePassword")
                        ?: error("key.properties 缺少 storePassword")
            }
        }
    }

    // Release signing policy:
    // - key.properties present (injected by CI from secrets for `v*` tags) →
    //   use the real release keystore, so GitHub Release APKs are properly signed.
    // - otherwise → fall back to the public debug key so local
    //   `flutter build apk --release` still works during development.
    // NOTE: APKs published through the GitHub Release are only real-signed when
    // built from a `v*` tag with ANDROID_KEYSTORE_BASE64 / KEYSTORE_PASSWORD /
    // KEY_ALIAS / KEY_PASSWORD repository secrets configured. Without them they
    // ship debug-signed (public AOSP key — anyone could re-sign and hijack
    // updates, and Play Store rejects them).
    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}