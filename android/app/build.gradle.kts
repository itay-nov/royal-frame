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
        versionCode = 3
        versionName = "1.0.2"
    }


    buildTypes {
    getByName("release") {
        // וודא שאלו הערכים:
        isMinifyEnabled = true  // זה ה-Code shrinking שחסר
        isShrinkResources = true // זה מה שגרם לשגיאה
        
        // ... שאר ההגדרות שלך
    }
}
}

flutter {
    source = "../.."
}
