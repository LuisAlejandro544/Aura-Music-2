# Arquitectura de Aura Music e Integración Nativa en Rust

## 1. Estado actual (Reproducción Media3 + Descarga `yt-dlp` + Rust `aura_yt_engine`)

- **Interfaz**: Flutter + Dart en modo claro cálido (*Acoustic Warmth*: `#F9F6F0`, `#F0EBE1`, `#2C2524`, `#D96B43`, `#E5A93B`).
- **Compuerta de permisos previos (`PermissionsScreen`)**: Antes de entrar a `AppShell`, la app verifica y solicita `POST_NOTIFICATIONS` (Android 13+) y explica el modelo privado de acceso bajo demanda (SAF + Photo Picker).
- **Motor de audio**: `androidx.media3:media3-exoplayer` + `media3-session` dentro de `AuraPlaybackService.kt`.
- **Importación privada**: Storage Access Framework (`AuraSafImporter.kt`) con permisos persistentes (`takePersistableUriPermission`) sobre archivos/carpetas elegidas por el usuario.
- **Edición de metadatos y carátula WebP sin pérdida**:
  - `EditTrackMetadataScreen` + `AuraArtworkProcessor.kt` (`Dispatchers.IO` + `ImageDecoder` API 28+) para conversión a WebP sin pérdida en `filesDir/custom_artworks/`.
  - Persistencia en SQLite (`LibraryDatabase` v2) preservando ediciones personalizadas.
- **Arquitecturas Android soportadas**: `armeabi-v7a` (32 bits) y `arm64-v8a` (64 bits), `minSdk = 28` (Android 9+).

---

## 2. Motor actual de Rust (`aura_music/rust/aura_yt_engine`) + `yt-dlp`

Aura Music ya integra Rust en producción mediante el crate `aura_yt_engine` (licencia `MIT OR Apache-2.0`), compilado obligatoriamente con `cargo-ndk` para 32 y 64 bits desde `android/app/build.gradle.kts` (con alineación de página de 16 KB `-Wl,-z,max-page-size=16384`):

### Papel 1 — Runtime QuickJS-ng en Rust (`libaura_qjs.so`) para `yt-dlp-ejs`
- **Archivo**: `aura_music/rust/aura_yt_engine/src/bin/aura_qjs.rs` (crate `rquickjs 0.14`, licencia MIT).
- **Por qué Rust + QuickJS-ng en lugar de Deno o WebView**:
  - Deno no ofrece binarios estáticos Android ARMv7 (32 bits) confiables y añade un runtime muy pesado.
  - `QuickJS-ng` compilado con `cargo-ndk` soporta nativamente tanto `armeabi-v7a` (32 bits) como `arm64-v8a` (64 bits) sin depender de Node.js ni WebView.
  - Implementa el protocolo CLI exacto de `QuickJsRuntime` / `QuickJSJCP` esperado por `yt-dlp`: `--help`/`--version` (`QuickJS-ng version 0.12.0 (aura-rust)`) y `--script <archivo.js>` con captura de `console.log`/`print` sobre un hilo dedicado con pila de 16 MB.
- **Empaquetado Android**: Se copia como `jniLibs/<abi>/libaura_qjs.so` con `android:extractNativeLibs="true"` y `useLegacyPackaging = true` para que Python pueda lanzarlo desde `context.applicationInfo.nativeLibraryDir` cumpliendo las políticas SELinux de Android 9–16.

### Papel 2 — Verificación e incrustación nativa de audio (`libaura_yt_rust.so`)
- **Archivo**: `aura_music/rust/aura_yt_engine/src/lib.rs` (crates `lofty 0.22`, `jni 0.21`, `serde`, `serde_json`; licencias MIT/Apache-2.0).
- **Bridge Kotlin**: `AuraRustYtBridge.kt`.
- **Funciones JNI**:
  1. `nativeParseAndCanonicalizeUrl`: limpia enlaces de YouTube (`youtu.be`, `watch`, `shorts`, `embed`, `live`), elimina parámetros de rastreo como `?si=` y valida el ID de 11 caracteres antes de invocar Python.
  2. `nativeVerifyAndTagAudioFile`: valida los *magic bytes* del contenedor descargado (`MP4/M4A`, `WebM/MKV`, `OGG`, `FLAC`, `WAV`, `MP3`) rechazando páginas HTML de bloqueo o respuestas corruptas; inspecciona propiedades técnicas (`sampleRateHz`, `bitrateKbps`, `channels`, `durationMs`, `mimeType`) con `lofty` e incrusta título, artista, álbum y carátula cuando el contenedor lo admite, sin necesitar FFmpeg GPL.

### Orquestación mínima en Python (`Chaquopy 17.2.0`)
- **Archivo**: `aura_music/android/app/src/main/python/aura_yt_engine.py`.
- **Dependencias exactas**: `yt-dlp --no-deps`, `yt-dlp-ejs --no-deps`, `certifi` sobre Python `3.11`.
- Selecciona flujos directos de audio (`m4a`/`opus`/`best`) reproducibles por Media3 ExoPlayer sin transcodificación FFmpeg y usa `js_runtimes={'quickjs': {'path': quickjs_path}}`.
- Todo el flujo se ejecuta en `Dispatchers.IO` dentro de `AuraYtDownloader.kt`, reportando progreso por `EventChannel` a `DownloadUrlScreen`.

---

## 3. Siguiente etapa en Rust (Fase 3: DSP de audio `aura_dsp`)

Toda la UI y los providers de Flutter dependen de la interfaz abstracta `AudioEnginePort` (`lib/core/audio/audio_engine_port.dart`):
1. Añadir módulos DSP en `aura_music/rust/` (por ejemplo `symphonia` / `rubato` / ecualizador paramétrico Biquad / FFT / ReplayGain bajo MIT/Apache-2.0).
2. Acoplar un `AudioProcessor` personalizado en `AuraPlaybackService.kt` enviando buffers PCM por JNI, o extender `AudioEnginePort` vía FFI.

---

## 4. Compilar el APK para Uptodown / distribución directa

Debido a que Chaquopy no admite `splits.abi` (`--split-per-abi`), cada arquitectura se compila de forma independiente mediante `--target-platform`:

```bash
cd aura_music
flutter pub get

# 64 bits (arm64-v8a)
flutter build apk --release --target-platform android-arm64

# 32 bits (armeabi-v7a)
flutter build apk --release --target-platform android-arm
```

En GitHub Actions (`.github/workflows/build-debug-apk.yml`), ambas compilaciones se ejecutan automáticamente y publican dos artifacts independientes:
- `aura-music-debug-arm64-v8a` (`app-arm64-v8a-debug.apk`, 64 bits)
- `aura-music-debug-armeabi-v7a` (`app-armeabi-v7a-debug.apk`, 32 bits)
