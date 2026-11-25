# Arquitectura de Aura Music e Integración Nativa en Rust

## 1. Estado actual (Reproducción Media3 + Descarga `yt-dlp` + Rust `aura_yt_engine`)

- **Interfaz**: Flutter + Dart con sistema de tema configurable Claro/Oscuro/Sistema (*Acoustic Warmth*: Claro `#F9F6F0` / Oscuro `#171413`, con `AuraPalette` `ThemeExtension` y `SettingsScreen`).
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

### Orquestación mínima y auto-actualizador en Python (`Chaquopy 17.2.0`)
- **Archivo**: `aura_music/android/app/src/main/python/aura_yt_engine.py` (con tests unitarios en `aura_music/test/python/test_aura_yt_engine.py`).
- **Dependencias base**: `yt-dlp --no-deps`, `yt-dlp-ejs --no-deps`, `certifi` sobre Python `3.11`.
- Selecciona flujos directos de audio (`m4a`/`opus`/`best`) reproducibles por Media3 ExoPlayer sin transcodificación FFmpeg y usa `js_runtimes={'quickjs': {'path': quickjs_path}}`.
- **Auto-actualizador desde PyPI sin recompilar APK**:
  - Consulta la API JSON oficial de PyPI para `yt-dlp` y `yt-dlp-ejs`, descarga únicamente wheels Python puros (`py3-none-any.whl`), verifica su digest **SHA-256** y previene ataques **ZipSlip** antes de extraerlos en `filesDir/yt_dlp_updates/`.
  - Prioriza ese directorio en `sys.path[0]`, recarga `sys.modules` en caliente y permite restaurar las versiones originales incluidas en el APK en cualquier momento.
  - `AuraYtDownloader.kt` ejecuta todo el flujo en `Dispatchers.IO` bajo un `Mutex` exclusivo (`engineOpMutex`), comprueba actualizaciones automáticamente cada 24 horas (configurable) antes de descargar y reporta progreso por `EventChannel` (`downloadProgress` / `ytUpdateProgress`) hacia `DownloadUrlScreen` y `SettingsScreen`.

---

## 3. Motor DSP nativo en Rust (`aura_music/rust/aura_dsp` -> `libaura_dsp.so`)

Aura Music integra procesamiento de audio en tiempo real mediante el crate `aura_dsp` (licencia `MIT OR Apache-2.0`), compilado obligatoriamente con `cargo-ndk` para `armeabi-v7a` y `arm64-v8a` hacia `rustDspJniLibs/` (separado de `rustJniLibs/`):

### Integración con Media3 ExoPlayer sin bloqueos
- **Bridge Kotlin (`AuraRustDspBridge.kt`)**: Carga `libaura_dsp.so`, restaura y persiste las preferencias del ecualizador en `SharedPreferences` (`aura_dsp_prefs`) incluso antes de abrir la UI, y sincroniza los parámetros con Rust mediante variables atómicas lock-free (`AtomicBool`, `AtomicI32`, `AtomicU64`).
- **AudioProcessor (`AuraRustDspProcessor.kt`)**: Extiende `BaseAudioProcessor` y se inyecta en `DefaultAudioSink` mediante un `DefaultRenderersFactory` personalizado dentro de `AuraPlaybackService.kt`.
- **Zero-copy JNI (`aura_dsp/src/lib.rs`)**: Procesa in-place el `DirectByteBuffer` de salida para formatos `PCM 16-bit` y `PCM 32-bit float` sin asignaciones de memoria en el hilo de audio.

### Cadena DSP implementada y UI comprensible (`EqualizerScreen`)
1. **Preamp** (`-6 dB` a `+6 dB` en UI, hasta `±12 dB` en motor).
2. **Ecualizador Biquad IIR de 5 bandas en serie** (hasta 8 canales, con límite seguro de Nyquist al 45% de la tasa de muestreo):
   - `60 Hz` (*Low-Shelf*): **Subgraves** — vibración y cuerpo profundo.
   - `230 Hz` (*Peaking EQ*): **Graves** — calidez, bajo y golpe.
   - `910 Hz` (*Peaking EQ*): **Voces** — claridad de voz e instrumentos.
   - `3.6 kHz` (*Peaking EQ*): **Presencia** — definición, guitarras y ataque.
   - `12 kHz` (*High-Shelf*): **Brillo** — aire, platillos y detalle fino.
3. **Limitador suave anti-distorsión (`soft-knee tanh`)**: Evita saturación digital o chasquidos cuando se refuerzan múltiples bandas.
4. **Siguientes extensiones DSP planeadas**: Normalización ReplayGain / LUFS y análisis espectral FFT de baja latencia para visualizador en `FullPlayerScreen`.

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
