import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

// Load signing config from keystore.properties (local) or environment variables (CI)
val keystorePropertiesFile = rootProject.file("keystore.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.examsaathi.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
                ?: System.getenv("KEY_ALIAS") ?: "androiddebugkey"
            keyPassword = keystoreProperties.getProperty("keyPassword")
                ?: System.getenv("KEY_PASSWORD") ?: "android"
            storeFile = (keystoreProperties.getProperty("storeFile")
                ?: System.getenv("KEYSTORE_PATH"))?.let { file(it) }
                ?: file("${System.getProperty("user.home")}/.android/debug.keystore")
            storePassword = keystoreProperties.getProperty("storePassword")
                ?: System.getenv("STORE_PASSWORD") ?: "android"
        }
    }

    defaultConfig {
        applicationId = "com.examsaathi.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
            // ProGuard disabled — re-enable once crash is diagnosed
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )
            firebaseCrashlytics {
                mappingFileUploadEnabled = false
            }
        }
        debug {
            isMinifyEnabled = false
        }
    }
}

flutter {
    source = "../.."
}
