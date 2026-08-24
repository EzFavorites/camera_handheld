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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.camera.camera_handheld"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
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
        val keystoreProperties = java.util.Properties()
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
