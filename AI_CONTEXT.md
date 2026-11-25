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
   - **Python 3.12 minimalista (`Chaquopy 17.2.0`, MIT)**: En `aura_music/android/app/build.gradle.kts` solo se instalan `yt-dlp --no-deps`, `yt-dlp-ejs --no-deps` y `certifi`, con `extractPackages("yt_dlp_ejs", "certifi")` para que `importlib.resources` y `cacert.pem` funcionen en disco.
   - **QuickJS-ng en Rust (`rquickjs` -> `libaura_qjs.so`)**: Compilado en `aura_music/rust/aura_yt_engine/src/bin/aura_qjs.rs` como ejecutable CLI compatible con `QuickJsRuntime` de `yt-dlp` (`--help` / `--version` y `--script <archivo.js>`) en `armeabi-v7a` y `arm64-v8a`. Empaquetado en `jniLibs/<abi>/libaura_qjs.so` con `android:extractNativeLibs="true"` y `useLegacyPackaging = true` para ejecutarse desde `nativeLibraryDir`.
   - **Segundo rol nativo de Rust (`lofty` + `jni` -> `libaura_yt_rust.so`)**: `AuraRustYtBridge.kt` invoca a Rust para canonicalizar URLs de YouTube (limpiando `?si=`, extrayendo ID de 11 caracteres), validar *magic bytes* de contenedores de audio (rechazando respuestas HTML/JSON corruptas), inspeccionar duración/bitrate/sample rate e incrustar etiquetas y carátula sin usar FFmpeg GPL.
   - **No hay WebView**: Se omite por decisión explícita; `aura_yt_engine.py` descarga flujos de audio directos (`m4a`/`webm`/mejor audio sin recodificación) y reintenta con `player_client=['android_vr', 'tv', 'web']` en caso necesario.
3. **Desacoplamiento del motor (`AudioEnginePort`)**:
   - Las pantallas y `Provider`s solo hablan con `AudioEnginePort` (`lib/core/audio/audio_engine_port.dart`).
   - Hoy lo implementa `ExoPlayerBridge` (`com.auramusic.player/audio` y `/events`), cubriendo reproducción Media3, SAF, conversión WebP y descarga `yt-dlp`.
4. **Compuerta previa de permisos (`_PermissionsEntryGate` + `PermissionsScreen`)**:
   - `main.dart` evalúa `Permission.notification.status` y `SharedPreferences` antes de montar `AppShell`.
   - En Android 13+, `POST_NOTIFICATIONS` se solicita antes de entrar a la app; si el usuario lo deniega permanentemente, ofrece `openAppSettings()` y una salida controlada.
5. **Concurrencia fuera del hilo principal**:
   - Extracción SAF (`AuraSafImporter.kt` + `AuraTrackMetadata.kt`): `Dispatchers.IO` con `Semaphore(4)`.
   - Conversión WebP (`AuraArtworkProcessor.kt`): `Dispatchers.IO` con `ImageDecoder` (API 28+) y `Bitmap.recycle()`.
   - Descarga y verificación (`AuraYtDownloader.kt`): `Dispatchers.IO` (Rust URL -> Chaquopy `aura_yt_engine.py` -> WebP -> Rust Lofty).
6. **Persistencia y protección de ediciones del usuario (`LibraryDatabase` v2)**:
   - SQLite guarda `originalArtworkPath` y `hasCustomMetadata`.
   - Las pistas descargadas desde URL se guardan en `filesDir/downloads/`, sus carátulas WebP en `filesDir/custom_artworks/`, y las ediciones personalizadas no se sobrescriben al re-importar.

---

## 3. Sistema visual ("Acoustic Warmth")

- **Modo claro cálido fijo**:
  - Fondo: `#F9F6F0` (`AuraColors.background`)
  - Superficie secundaria / barra inferior: `#F0EBE1` (`AuraColors.surface`)
  - Tarjetas elevadas: `#FFFFFF` (`AuraColors.surfaceElevated`)
  - Texto primario: `#2C2524` | Texto secundario: `#8C827B`
  - Acento principal: `#D96B43` (terracota) | Ámbar: `#E5A93B` | Lossless/éxito: `#3B8A6E`
  - Bordes: `#E3DED4`
- **Navegación**:
  - Barra inferior custom `_AuraBottomBar` (`Inicio`, `Buscar`, `Biblioteca`) dentro de `app_shell.dart`, más `MiniPlayer` flotante y navegación por rutas a `FullPlayerScreen`, `CollectionDetailScreen`, `EditTrackMetadataScreen` y `DownloadUrlScreen`.

---

## 4. Dependencias activas y licencias

Todas las librerías en `aura_music/pubspec.yaml`, `aura_music/android/app/build.gradle.kts` y `aura_music/rust/aura_yt_engine/Cargo.toml` evitan licencias virales (GPL/AGPL prohibidas) y no exigen atribución obligatoria en UI:
- **Flutter**: `provider`, `sqflite`, `path_provider`, `path`, `shared_preferences`, `flutter_animate`, `permission_handler`, `image_picker` (MIT/BSD/Apache-2.0).
- **Android / Kotlin**: `androidx.media3:*` (`1.4.1`), `androidx.documentfile`, `kotlinx-coroutines-android`, `androidx.core:core-ktx` (Apache-2.0), `com.chaquo.python` (`17.2.0`, MIT).
- **Python (Chaquopy 3.12 mínimo)**: `yt-dlp` (Unlicense), `yt-dlp-ejs` (Unlicense/ISC), `certifi` (MPL-2.0 limitada a su bundle de certificados raíz CA, sin efecto viral ni atribución en UI).
- **Rust (`aura_yt_engine`)**: `rquickjs` `0.14` (MIT), `lofty` `0.22` (MIT/Apache-2.0), `jni` `0.21` (MIT/Apache-2.0), `serde` / `serde_json` (MIT/Apache-2.0).
