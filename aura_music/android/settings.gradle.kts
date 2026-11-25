// =============================================================================
// settings.gradle.kts — Configuración de módulos y repositorios Gradle
// -----------------------------------------------------------------------------
// Carga el SDK de Flutter desde local.properties para compilar tanto desde
// línea de comandos (gradlew) como desde Android Studio o un entorno móvil/CI.
// =============================================================================

pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        val localProps = file("local.properties")
        if (localProps.exists()) {
            localProps.inputStream().use { properties.load(it) }
        }
        val path = properties.getProperty("flutter.sdk")
            ?: System.getenv("FLUTTER_ROOT")
            ?: error("flutter.sdk not set in local.properties or FLUTTER_ROOT")
        path
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.5.2" apply false
    id("org.jetbrains.kotlin.android") version "2.0.20" apply false
}

include(":app")
