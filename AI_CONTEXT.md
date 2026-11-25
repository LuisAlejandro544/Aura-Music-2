# Contexto Técnico para IA (`AI_CONTEXT.md`)

Este archivo resume las decisiones arquitectónicas, límites del entorno y flujos internos de **Aura Music** para que cualquier modelo de IA entienda el proyecto sin asumir comportamientos falsos.

---

## 1. Dos mundos dentro del mismo repositorio

1. **Aplicación real (`aura_music/`)**: App móvil Android escrita en **Flutter/Dart + Kotlin + Rust + Python (Chaquopy)** (`minSdk = 28`, `targetSdk = 36`, ABIs `armeabi-v7a` y `arm64-v8a`).
2. **Wrapper web en raíz (`src/`)**: Aplicación React + Vite mínima que únicamente renderiza `"Hello World"` (`src/App.tsx`). Existe solo para el servidor web de previsualización en puerto 3000. **No implementa el reproductor ni debe confundirse con la app móvil.**
3. **Entorno de compilación**: En el contenedor local no hay Flutter, Cargo ni Android SDK; la compilación real de APKs ocurre en GitHub Actions (`.github/workflows/build-debug-apk.yml`) pensado para flujo sin PC desde teléfono.

---

## 2. Principios de arquitectura no negociables

1. **Privacidad por diseño (SAF sin escaneo global)**:
   - Prohibido añadir `READ_EXTERNAL_STORAGE` o `MANAGE_EXTERNAL_STORAGE`.
   - Toda importación local pasa por `AuraSafImporter.kt` (`ACTION_OPEN_DOCUMENT` / `ACTION_OPEN_DOCUMENT_TREE`) con `takePersistableUriPermission`.
   - Las carátulas personalizadas usan `image_picker` (Photo Picker / selector del sistema), que tampoco requiere `READ_MEDIA_IMAGES`.
2. **Motor `yt-dlp` puro + `yt-dlp-ejs` + Rust (sin WebView ni dependencias GPL)**:
   - **Python 3.11 minimalista (`Chaquopy 17.2.0`, MIT)**: En `aura_music/android/app/build.gradle.kts` solo se instalan `yt-dlp --no-deps`, `yt-dlp-ejs --no-deps` y `certifi`, con `extractPackages("yt_dlp_ejs", "certifi")` para que `importlib.resources` y `cacert.pem` funcionen en disco.
   - **QuickJS-ng en Rust (`rquickjs` -> `libaura_qjs.so`)**: Compilado en `aura_music/rust/aura_yt_engine/src/bin/aura_qjs.rs` como ejecutable CLI compatible con `QuickJsRuntime` de `yt-dlp` (`--help` / `--version` y `--script <archivo.js>`) en `armeabi-v7a` y `arm64-v8a`. Empaquetado en `jniLibs/<abi>/libaura_qjs.so` con `android:extractNativeLibs="true"` y `useLegacyPackaging = true` para ejecutarse desde `nativeLibraryDir`.
   - **Segundo rol nativo de Rust (`lofty` + `jni` -> `libaura_yt_rust.so`)**: `AuraRustYtBridge.kt` invoca a Rust para canonicalizar URLs de YouTube (limpiando `?si=`, extrayendo ID de 11 caracteres), validar *magic bytes* de contenedores de audio (rechazando respuestas HTML/JSON corruptas), inspeccionar duración/bitrate/sample rate e incrustar etiquetas y carátula sin usar FFmpeg GPL.
   - **No hay WebView**: Se omite por decisión explícita; `aura_yt_engine.py` descarga flujos de audio directos (`m4a`/`webm`/mejor audio sin recodificación) y reintenta con `player_client=['android_vr', 'tv', 'web']` en caso necesario.
   - **Auto-actualizador PyPI de `yt-dlp` y `yt-dlp-ejs`**: Sin necesidad de recompilar el APK ni depender de `pip` en runtime, `aura_yt_engine.py` consulta la API JSON oficial de PyPI (`urllib.request` + `certifi`), compara versiones PEP-440/CalVer, descarga únicamente wheels puros (`py3-none-any.whl`), verifica su digest **SHA-256** y rutas seguras (anti-ZipSlip), los extrae en `filesDir/yt_dlp_updates/` y recarga `sys.modules` en caliente priorizando `sys.path[0]`. `AuraYtDownloader.kt` serializa operaciones de motor con `Mutex` (`engineOpMutex`), persiste preferencias en `aura_yt_prefs` y realiza una comprobación silenciosa cada 24 h antes de descargar (si el auto-actualizador está activo).
3. **Desacoplamiento del motor (`AudioEnginePort`) y cola fluida**:
   - Las pantallas y `Provider`s solo hablan con `AudioEnginePort` (`lib/core/audio/audio_engine_port.dart`).
   - Hoy lo implementa `ExoPlayerBridge` (`com.auramusic.player/audio` y `/events`), cubriendo reproducción Media3, inserción/reordenamiento/eliminación incremental de cola (`addMediaItem`/`moveMediaItem`/`removeMediaItem`), control del ecualizador Rust, SAF, conversión WebP, limpieza de archivos descargados, descarga `yt-dlp` y gestión de actualizaciones/restauración de `yt-dlp` + `yt-dlp-ejs` (`ytUpdateProgress` vía `EventChannel`).
4. **Motor DSP nativo en Rust (`aura_dsp` -> `libaura_dsp.so`)**:
   - Compilado con `cargo-ndk` para 32 y 64 bits hacia `rustDspJniLibs/` (separado de `rustJniLibs/`).
   - `AuraRustDspProcessor` implementa `BaseAudioProcessor` dentro de `DefaultAudioSink` en `AuraPlaybackService.kt`, procesando buffers PCM `16-bit` y `float32` por `DirectByteBuffer` con parámetros atómicos lock-free (`AtomicBool`/`AtomicI32`) en `aura_dsp`.
   - Expone ecualizador Biquad IIR de 5 bandas, Preamp y limitador suave `tanh`, persistidos en `SharedPreferences` (`aura_dsp_prefs`).
5. **Compuerta previa de permisos (`_PermissionsEntryGate` + `PermissionsScreen`)**:
   - `main.dart` evalúa `Permission.notification.status` y `SharedPreferences` antes de montar `AppShell`.
   - En Android 13+, `POST_NOTIFICATIONS` se solicita antes de entrar a la app; si el usuario lo deniega permanentemente, ofrece `openAppSettings()` y una salida controlada.
6. **Concurrencia fuera del hilo principal**:
   - Extracción SAF (`AuraSafImporter.kt` + `AuraTrackMetadata.kt`): `Dispatchers.IO` con `Semaphore(4)`, contador `AtomicInteger` en orden monótono y caché atómica de carátulas.
   - Conversión WebP (`AuraArtworkProcessor.kt`): `Dispatchers.IO` con `ImageDecoder` (API 28+) y `Bitmap.recycle()`.
   - Descarga, actualización PyPI y verificación (`AuraYtDownloader.kt`): `Dispatchers.IO` (Rust URL -> chequeo 24h / Chaquopy `aura_yt_engine.py` con arranque diferido al descargar -> WebP -> Rust Lofty). `getEngineStatus(includePython = false)` no inicializa Python si aún no fue usado; `SettingsScreen` pasa `includePython = true` para mostrar versiones exactas.
7. **Persistencia, limpieza física y protección de ediciones del usuario (`LibraryDatabase` v2)**:
   - SQLite guarda `originalArtworkPath` y `hasCustomMetadata`.
   - Las pistas descargadas desde URL se guardan en `filesDir/aura_downloads/`, sus carátulas WebP en `filesDir/custom_artworks/`, y las ediciones personalizadas no se sobrescriben al re-importar.
   - Al eliminar una pista (`LibraryProvider.removeTrack` -> `deleteTrackResources`), se eliminan sus carátulas personalizadas/caché y, si su URI apunta dentro de `filesDir/aura_downloads/`, se borra también el archivo físico de audio.

---

## 3. Sistema visual ("Acoustic Warmth" Claro y Oscuro)

- **Apariencia configurable (`SettingsProvider` + `AuraPalette` / `ThemeExtension`)**:
  - La app inicia por defecto en **Modo Claro (`ThemeMode.light`)**, con selector persistente en `SettingsScreen` para **Claro**, **Oscuro** o **Sistema** (`SharedPreferences`: `aura_theme_mode`).
  - **Modo Claro (`AuraColors`)**: Fondo `#F9F6F0` | Superficie `#F0EBE1` | Tarjetas `#FFFFFF` | Texto `#2C2524` / `#8C827B` | Terracota `#D96B43` | Ámbar `#E5A93B` | Salvia `#3B8A6E` | Bordes `#E3DED4`.
  - **Modo Oscuro (*Acoustic Warmth Dark* — `AuraDarkColors`)**: Fondo `#171413` | Superficie `#211D1B` | Tarjetas `#2A2522` | Texto `#F4EFE8` / `#B3AAA2` | Terracota `#E07A54` | Ámbar `#EBB44D` | Salvia `#4DA887` | Bordes `#36302C`.
  - Todas las pantallas y hojas modales consumen colores desde `AuraTheme.of(context)` y `main.dart` sincroniza dinámicamente `SystemUiOverlayStyle`.
- **Navegación**:
  - Barra inferior custom `_AuraBottomBar` (`Inicio`, `Buscar`, `Biblioteca`) dentro de `app_shell.dart`, más `MiniPlayer` flotante y navegación por rutas a `FullPlayerScreen`, `EqualizerScreen`, `CollectionDetailScreen`, `EditTrackMetadataScreen`, `DownloadUrlScreen` y `SettingsScreen` (accesible desde la cabecera de `HomeScreen` y la tarjeta técnica de `DownloadUrlScreen`).

---

## 4. Dependencias activas y licencias

Todas las librerías en `aura_music/pubspec.yaml`, `aura_music/android/app/build.gradle.kts`, `aura_music/rust/aura_yt_engine/Cargo.toml` y `aura_music/rust/aura_dsp/Cargo.toml` evitan licencias virales (GPL/AGPL prohibidas) y no exigen atribución obligatoria en UI:
- **Flutter**: `provider`, `sqflite`, `path_provider`, `path`, `shared_preferences`, `flutter_animate`, `permission_handler`, `image_picker` (MIT/BSD/Apache-2.0).
- **Android / Kotlin**: `androidx.media3:*` (`1.4.1`), `androidx.documentfile`, `kotlinx-coroutines-android`, `androidx.core:core-ktx` (Apache-2.0), `com.chaquo.python` (`17.2.0`, MIT).
- **Python (Chaquopy 3.11 mínimo)**: `yt-dlp` (Unlicense), `yt-dlp-ejs` (Unlicense/ISC), `certifi` (MPL-2.0 limitada a su bundle de certificados raíz CA, sin efecto viral ni atribución en UI).
- **Rust (`aura_yt_engine`)**: `rquickjs` `0.14` (MIT), `lofty` `0.22` (MIT/Apache-2.0), `jni` `0.21` (MIT/Apache-2.0), `serde` / `serde_json` (MIT/Apache-2.0).
- **Rust (`aura_dsp`)**: DSP Biquad IIR + limitador `tanh` en Rust puro + `jni` `0.21`, `serde` / `serde_json` (MIT/Apache-2.0).
