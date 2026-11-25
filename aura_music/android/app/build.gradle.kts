// =============================================================================
// app/build.gradle.kts — Configuración de compilación del APK de Aura Music
// -----------------------------------------------------------------------------
// - minSdk = 28 (Android 9 Pie): solicitado explícitamente por el proyecto.
//   Permite usar Media3 ExoPlayer, NotificationChannel nativo y Storage Access
//   Framework moderno sin parches heredados de Android 5-8.
// - abiFilters: incluye arquitecturas de 32 bits (armeabi-v7a) y 64 bits
//   (arm64-v8a) para compatibilidad total al distribuir el APK en Uptodown u
//   otras tiendas de terceros.
// - Sin dependencias Rust activas en esta versión inicial; la capa de puente
//   está preparada en Dart para la integración final.
// =============================================================================

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.auramusic.player"
    compileSdk = 35
    ndkVersion = "26.3.11579264"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.auramusic.player"
        minSdk = 28
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"

        // Soporte explícito para dispositivos móviles de 32 bits y 64 bits
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    buildTypes {
        release {
            // Para publicar en Uptodown o distribución directa, configura tu
            // keystore en android/key.properties antes de firmar la versión final.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("debug")
        }
        debug {
            isMinifyEnabled = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Media3 ExoPlayer y MediaSession (Licencia Apache-2.0)
    val media3Version = "1.4.1"
    implementation("androidx.media3:media3-exoplayer:$media3Version")
    implementation("androidx.media3:media3-session:$media3Version")
    implementation("androidx.media3:media3-common:$media3Version")

    // DocumentFile para recorrer carpetas elegidas por el usuario vía SAF (Apache-2.0)
    implementation("androidx.documentfile:documentfile:1.0.1")

    // Kotlin Coroutines para no bloquear nunca el hilo principal UI (Apache-2.0)
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    // Utilidades AndroidX Core (Apache-2.0)
    implementation("androidx.core:core-ktx:1.13.1")
}
