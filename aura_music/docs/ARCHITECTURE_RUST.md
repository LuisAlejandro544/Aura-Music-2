# Arquitectura de Aura Music y Ruta de Integración con Rust

## 1. Estado actual (Fase 1: Diseño + ExoPlayer en Android 9+)
- **Interfaz**: Flutter + Dart en modo claro cálido (*Acoustic Warmth*: `#F9F6F0`, `#F0EBE1`, `#2C2524`, `#D96B43`, `#E5A93B`).
- **Motor de audio**: `androidx.media3:media3-exoplayer` + `media3-session` dentro de `AuraPlaybackService.kt`.
- **Importación privada**: Storage Access Framework (`AuraSafImporter.kt`) con permisos persistentes (`takePersistableUriPermission`) sobre archivos/carpetas elegidas por la usuaria, sin escanear todo el teléfono.
- **Concurrencia**: Kotlin Coroutines (`Dispatchers.IO`) para lectura de metadatos y extracción de carátulas en `cacheDir`.
- **Arquitecturas Android soportadas**: `armeabi-v7a` (32 bits) y `arm64-v8a` (64 bits), `minSdk = 28` (Android 9+).

## 2. Cómo se conectará Rust en la versión final
Toda la UI y los providers de Flutter dependen únicamente de la interfaz abstracta `AudioEnginePort` (`lib/core/audio/audio_engine_port.dart`) y del `AudioEngineBackend` enum (`lib/core/models/audio_track.dart`).

En la versión final con Rust:
1. Se añadirá un crate en `aura_music/rust/` (ej. `aura_dsp` con `symphonia` / `rubato` / ecualizador paramétrico Biquad / análisis FFT / ReplayGain — verificando siempre licencias permisivas MIT/Apache-2.0).
2. Se integrará en `android/app/build.gradle.kts` mediante `cargo-ndk` compilando obligatoriamente para `armeabi-v7a` y `arm64-v8a` en cada build de Gradle/APK.
3. En Kotlin (`AuraPlaybackService.kt`), se podrá acoplar un `AudioProcessor` personalizado de Media3 que envíe buffers PCM por JNI al pipeline DSP de Rust, o implementar un `RustAudioBridge` que implemente `AudioEnginePort` en Dart vía FFI (`flutter_rust_bridge`).

## 3. Compilar el APK para Uptodown / distribución directa
```bash
cd aura_music
flutter pub get
flutter build apk --release
```
O generando APKs optimizados por arquitectura (32 y 64 bits):
```bash
flutter build apk --release --split-per-abi
```
