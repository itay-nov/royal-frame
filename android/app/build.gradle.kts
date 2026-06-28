plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.itay.royalframegame"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.itay.royalframegame"
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        // versionCode and versionName are injected by the Flutter Gradle plugin
        // from pubspec.yaml (version: 1.0.3+4 → versionName=1.0.3, versionCode=4).
        // Do NOT hardcode them here.
        versionCode = 7
        versionName = "1.1.0"
    }

    buildTypes {
        getByName("release") {
            isMinifyEnabled = true
            isShrinkResources = true
            // Uses Flutter's default debug signing for now.
            // Replace with a proper keystore config before publishing to Play Store.
        }
    }
}

flutter {
    source = "../.."
}
