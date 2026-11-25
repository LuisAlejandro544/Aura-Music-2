// =============================================================================
// app/build.gradle.kts — Configuración de compilación del APK de Aura Music
// -----------------------------------------------------------------------------
// - minSdk = 28 (Android 9 Pie): Media3 ExoPlayer, ImageDecoder WebP lossless,
//   Storage Access Framework y ejecución segura desde nativeLibraryDir.
// - Chaquopy 17.2.0 (Licencia MIT): intérprete Python 3.11 minimalista con
//   únicamente `yt-dlp --no-deps`, `yt-dlp-ejs --no-deps` y `certifi`
//   (Python 3.11 mantiene soporte nativo para 32 bits armeabi-v7a y 64 bits arm64-v8a).
// - Rust (`aura_yt_engine`, MIT/Apache-2.0): compilado obligatoriamente con
//   `cargo-ndk` para 32 bits (armeabi-v7a) y 64 bits (arm64-v8a), generando:
//     * `libaura_yt_rust.so` (JNI: verificación de audio y tagging con Lofty)
//     * `libaura_qjs.so` (binario QuickJS-ng en Rust para yt-dlp-ejs)
// =============================================================================

import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.chaquo.python")
}

val targetPlatformProp = (
    project.findProperty("auraAbi")
        ?: project.findProperty("aura-abi")
        ?: project.findProperty("target-platforms")
        ?: project.findProperty("target-platform")
    )?.toString()?.trim() ?: ""

val requestedAbis = when {
    targetPlatformProp == "android-arm" || targetPlatformProp == "armeabi-v7a" ->
        listOf("armeabi-v7a")
    targetPlatformProp == "android-arm64" || targetPlatformProp == "arm64-v8a" ->
        listOf("arm64-v8a")
    targetPlatformProp.contains(",") -> targetPlatformProp.split(",")
        .mapNotNull { token ->
            when (token.trim()) {
                "android-arm", "armeabi-v7a" -> "armeabi-v7a"
                "android-arm64", "arm64-v8a" -> "arm64-v8a"
                else -> null
            }
        }
        .distinct()
        .ifEmpty { listOf("armeabi-v7a", "arm64-v8a") }
    else -> listOf("armeabi-v7a", "arm64-v8a")
}

val isSplitPerAbi =
    project.findProperty("split-per-abi")?.toString()?.toBoolean() == true

val configuredNdkVersion = "28.2.13676358"

android {
    namespace = "com.auramusic.player"
    compileSdk = 36
    ndkVersion = configuredNdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.auramusic.player"
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"

        // Soporte explícito para 32 bits y 64 bits; cuando se compila con
        // --split-per-abi, Flutter configura splits.abi y AGP no permite
        // combinarlo simultáneamente con defaultConfig.ndk.abiFilters.
        if (!isSplitPerAbi) {
            ndk {
                abiFilters.clear()
                abiFilters.addAll(requestedAbis)
            }
        }
    }

    sourceSets {
        getByName("debug").jniLibs.directories.add(
            layout.buildDirectory.dir("rustJniLibs/debug").get().asFile.absolutePath
        )
        getByName("release").jniLibs.directories.add(
            layout.buildDirectory.dir("rustJniLibs/release").get().asFile.absolutePath
        )
    }

    packaging {
        jniLibs {
            useLegacyPackaging = true
            // Excluye explícitamente cualquier ABI ajena a requestedAbis (p. ej. x86_64 o la otra ABI ARM)
            // que Flutter Debug o dependencias nativas intenten empaquetar dentro del APK individual.
            if (!isSplitPerAbi) {
                val excludedAbis = listOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")
                    .filter { it !in requestedAbis }
                excludedAbis.forEach { abi ->
                    excludes += "lib/$abi/**"
                    excludes += "**/$abi/**"
                }
            }
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
            if (!isSplitPerAbi) {
                ndk {
                    abiFilters.clear()
                    abiFilters.addAll(requestedAbis)
                }
            }
        }
        debug {
            isMinifyEnabled = false
            if (!isSplitPerAbi) {
                ndk {
                    abiFilters.clear()
                    abiFilters.addAll(requestedAbis)
                }
            }
        }
    }
}

// Flutter Gradle Plugin inyecta todas las ABIs (incluida x86_64) en variantes Debug
// durante afterEvaluate. finalizeDsl limpia esa lista antes de crear las variantes
// para que Chaquopy, Flutter y AGP empaqueten exclusivamente requestedAbis.
androidComponents {
    finalizeDsl { extension ->
        if (!isSplitPerAbi) {
            extension.defaultConfig.ndk.abiFilters.clear()
            extension.defaultConfig.ndk.abiFilters.addAll(requestedAbis)
            extension.buildTypes.forEach { buildType ->
                buildType.ndk.abiFilters.clear()
                buildType.ndk.abiFilters.addAll(requestedAbis)
            }
        }
    }
}

chaquopy {
    defaultConfig {
        version = "3.11"
        System.getenv("CHAQUOPY_BUILD_PYTHON")
            ?.takeIf { it.isNotBlank() }
            ?.let { buildPython(it) }
        pip {
            // Intérprete mínimo: solo yt-dlp + yt-dlp-ejs + certifi sin
            // dependencias extra, pasando --no-deps mediante options().
            options("--no-deps")
            install("yt-dlp")
            install("yt-dlp-ejs")
            install("certifi")
        }
        // Necesario para importlib.resources en yt_dlp_ejs y certifi/cacert.pem
        extractPackages("yt_dlp_ejs", "certifi")
        pyc {
            src = true
            pip = true
            stdlib = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

// =============================================================================
// Compilación nativa de Rust (`aura_yt_engine`) con `cargo-ndk` para 32 y 64 bits
// =============================================================================
val rustCrateDir = file("../../rust/aura_yt_engine")

val cargoExecutable = listOf(
    File(System.getProperty("user.home"), ".cargo/bin/cargo"),
    File("/usr/local/cargo/bin/cargo")
).firstOrNull { it.exists() }?.absolutePath ?: "cargo"

val androidSdkDir: String by lazy {
    val localProps = Properties().apply {
        val f = rootProject.file("local.properties")
        if (f.exists()) f.inputStream().use { load(it) }
    }
    localProps.getProperty("sdk.dir")
        ?: System.getenv("ANDROID_HOME")
        ?: System.getenv("ANDROID_SDK_ROOT")
        ?: ""
}

fun abiToRustTriple(abi: String): String = when (abi) {
    "armeabi-v7a" -> "armv7-linux-androideabi"
    "arm64-v8a" -> "aarch64-linux-android"
    else -> error("ABI no soportada por Aura Music: $abi")
}

fun registerAuraRustTask(variant: String) {
    val capitalized = variant.replaceFirstChar { it.uppercaseChar() }
    val taskName = "compileAuraRust$capitalized"
    val outputDir = layout.buildDirectory.dir("rustJniLibs/$variant").get().asFile
    val abisToBuild = requestedAbis

    tasks.register<Exec>(taskName) {
        group = "rust"
        description = "Compila libaura_yt_rust.so y libaura_qjs.so para $variant (${abisToBuild.joinToString()})"
        workingDir = rustCrateDir
        inputs.property("requestedAbis", abisToBuild.joinToString(","))

        val ndkPath = if (androidSdkDir.isNotEmpty()) {
            "$androidSdkDir/ndk/$configuredNdkVersion"
        } else {
            System.getenv("ANDROID_NDK_HOME") ?: ""
        }

        val cmdArgs = mutableListOf(
            "ndk",
            "--platform", "28",
            "-o", outputDir.absolutePath
        )
        abisToBuild.forEach { abi ->
            cmdArgs.add("-t")
            cmdArgs.add(abi)
        }
        // Se compila siempre --release para que QuickJS-ng ejecute el solver AST
        // de YouTube a máxima velocidad incluso en APKs Debug.
        cmdArgs.addAll(listOf("build", "--release"))

        executable = cargoExecutable
        args = cmdArgs

        if (ndkPath.isNotEmpty()) {
            environment("ANDROID_NDK_HOME", ndkPath)
        }
        environment("RUSTFLAGS", "-C link-arg=-Wl,-z,max-page-size=16384")

        doFirst {
            outputDir.deleteRecursively()
            outputDir.mkdirs()
        }

        doLast {
            abisToBuild.forEach { abi ->
                val triple = abiToRustTriple(abi)
                val builtBin = File(rustCrateDir, "target/$triple/release/aura_qjs")
                if (!builtBin.exists()) {
                    throw GradleException("No se encontró el binario Rust QuickJS-ng en: ${builtBin.absolutePath}")
                }
                val abiOutDir = File(outputDir, abi).apply { mkdirs() }
                val destQjs = File(abiOutDir, "libaura_qjs.so")
                builtBin.copyTo(destQjs, overwrite = true)
                destQjs.setExecutable(true, false)
            }
        }
    }

    tasks.matching { it.name == "merge${capitalized}JniLibFolders" }.configureEach {
        dependsOn(taskName)
    }
}

registerAuraRustTask("debug")
registerAuraRustTask("release")

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
