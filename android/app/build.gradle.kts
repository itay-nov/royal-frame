import java.util.Properties
import java.io.FileInputStream

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
} else {
    println("Warning: key.properties not found")
}

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
   
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
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
        targetSdk = 36
        // versionCode and versionName are injected by the Flutter Gradle plugin
        // from pubspec.yaml (version: 1.1.1+10 → versionName=1.1.1, versionCode=10).
        // Do NOT hardcode them here.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        getByName("release") {
        signingConfig = signingConfigs.getByName("release")
            
        // הגדרות נוספות שמומלצות לפרודקשן
        isMinifyEnabled = true
        isShrinkResources = true
        proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Official Google Play In-App Review API. Platform use is isolated behind
    // the Android MethodChannel in MainActivity.
    implementation("com.google.android.play:review:2.0.2")
}
