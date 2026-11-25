# Arquitectura de Aura Music y Ruta de Integración con Rust

## 1. Estado actual (Fase 1: Diseño + ExoPlayer en Android 9+)
- **Interfaz**: Flutter + Dart en modo claro cálido (*Acoustic Warmth*: `#F9F6F0`, `#F0EBE1`, `#2C2524`, `#D96B43`, `#E5A93B`).
- **Compuerta de permisos previos (`PermissionsScreen`)**: Antes de entrar a `AppShell`, la app verifica y solicita con `permission_handler` el permiso de notificaciones multimedia (`POST_NOTIFICATIONS` en Android 13+) y explica el modelo privado de acceso bajo demanda (SAF + Photo Picker).
- **Motor de audio**: `androidx.media3:media3-exoplayer` + `media3-session` dentro de `AuraPlaybackService.kt`.
- **Importación privada**: Storage Access Framework (`AuraSafImporter.kt`) con permisos persistentes (`takePersistableUriPermission`) sobre archivos/carpetas elegidas por el usuario, sin escanear todo el teléfono.
- **Edición de metadatos y carátula WebP sin pérdida**:
  - Pantalla dedicada `EditTrackMetadataScreen` accesible desde `TrackOptionsSheet` para editar título, artista, álbum y carpeta/colección.
  - Selección de carátula personalizada desde la galería del sistema mediante `image_picker` (sin pedir acceso global al almacenamiento).
  - Conversión nativa en `AuraArtworkProcessor.kt` (Kotlin Coroutines sobre `Dispatchers.IO` + `ImageDecoder` API 28+): convierte la imagen a **WebP con compresión máxima sin pérdida** (`Bitmap.CompressFormat.WEBP_LOSSLESS` a calidad `100` en Android 11+ / `WEBP` a calidad `100` en Android 9–10) y la guarda de forma persistente en `filesDir/custom_artworks/`.
  - Persistencia en SQLite (`LibraryDatabase` v2) preservando ediciones personalizadas frente a re-importaciones y sincronizando en vivo la cola y notificación de `MediaSession`.
- **Concurrencia**: Kotlin Coroutines (`Dispatchers.IO`) para lectura de metadatos, extracción de carátulas en `cacheDir` y conversión WebP sin bloquear la UI.
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

En GitHub Actions (`.github/workflows/build-debug-apk.yml`), la compilación Debug usa `--split-per-abi` y publica dos artifacts independientes para descargar solo la arquitectura de tu teléfono:
- `aura-music-debug-arm64-v8a` (`app-arm64-v8a-debug.apk`, 64 bits)
- `aura-music-debug-armeabi-v7a` (`app-armeabi-v7a-debug.apk`, 32 bits)
