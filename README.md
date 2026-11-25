# Aura Music

Reproductor de música local y descargador de audio integrado para **Android 9+ (`minSdk = 28`)** construido con **Flutter + Dart**, motor nativo **Media3 ExoPlayer** en Kotlin, intérprete **Python 3.11 minimalista (Chaquopy)** con `yt-dlp` + `yt-dlp-ejs` + `certifi`, y motores nativos en **Rust (`aura_yt_engine` y `aura_dsp`)** con **QuickJS-ng (`rquickjs`)**, **Lofty** y procesamiento PCM Biquad en tiempo real, diseñado con estética cálida (*Acoustic Warmth*).

> **Nota sobre la estructura del repositorio:** La aplicación móvil real vive dentro de `aura_music/`. La raíz del repositorio contiene un wrapper web mínimo en React/Vite (`src/`) usado únicamente como vista de entorno web, además del workflow de compilación en `.github/workflows/build-debug-apk.yml`.

---

## Características principales

- **Explorar y streaming progresivo mientras se cachea (`ExploreScreen` + `AuraStreamCache.kt`)**:
  - Pestaña dedicada en la barra inferior (`Inicio`, `Explorar`, `Buscar`, `Biblioteca`) con categorías curadas por género/estado de ánimo, búsqueda online mediante `yt-dlp` (consultas o playlists públicas) e historial reciente guardado en `SharedPreferences`.
  - **Reproducción inmediata mientras se descarga en caché**: `AuraStreamCache.kt` combina `SimpleCache` (512 MB LRU en `cacheDir/aura_stream_cache`) + `CacheDataSource` + `ResolvingDataSource` de Media3 para reproducir desde los primeros fragmentos sin esperar a descargar toda la pista, conservando compatibilidad total con el Ecualizador y el Audio 8D en Rust.
  - Muestra barra de progreso de buffer en `FullPlayerScreen`, indicador `STREAM` / `CACHÉ` / `GUARDADA` y permite descargar cualquier tema a la biblioteca offline en un toque o eligiendo formato en `DownloadUrlScreen`.
- **Importación privada sin escaneo global**: Nunca solicita `READ_EXTERNAL_STORAGE` ni `MANAGE_EXTERNAL_STORAGE`. El usuario elige explícitamente canciones o carpetas mediante SAF (`AuraSafImporter.kt`) con permisos persistentes.
- **Descarga de audio desde URL (`DownloadUrlScreen` + `yt-dlp` + Rust)**:
  - Accesible desde el botón `+` (`ImportSourceSheet` -> *Descargar desde URL (yt-dlp)*), desde *Explorar* o desde el reproductor.
  - Intérprete **Python 3.11 minimalista** embebido con **Chaquopy 17.2.0** (MIT), instalando únicamente `yt-dlp --no-deps`, `yt-dlp-ejs --no-deps` y `certifi` (arranque diferido hasta iniciar una descarga o abrir *Explorar*).
  - **QuickJS-ng en Rust (`rquickjs` -> `libaura_qjs.so`)**: Ejecutable nativo para 32 y 64 bits empaquetado en `jniLibs` que resuelve los retos JS de `yt-dlp-ejs` sin necesidad de Node.js, Deno ni WebView.
  - **Validación y etiquetado nativo en Rust (`lofty` -> `libaura_yt_rust.so`)**: Canonicaliza URLs, verifica magic bytes del contenedor descargado (rechaza respuestas HTML/corruptas), extrae propiedades técnicas e incrusta metadatos y carátula WebP sin depender de FFmpeg GPL.
  - Al finalizar, registra la pista en SQLite (`filesDir/aura_downloads/`) y la reproduce automáticamente en `FullPlayerScreen`. Al eliminar una pista descargada de la biblioteca, borra también su archivo físico y carátulas asociadas.
- **Ecualizador y Audio 8D nativo en Rust (`EqualizerScreen` + `Spatial8dScreen` + `aura_dsp` -> `libaura_dsp.so`)**:
  - Procesamiento en tiempo real sin bloqueos mediante `AuraRustDspProcessor` conectado a `DefaultAudioSink` de Media3 ExoPlayer.
  - 5 bandas Biquad IIR con nombres entendibles (*Subgraves*, *Graves*, *Voces*, *Presencia*, *Brillo*), curva visual en vivo, perfiles rápidos (*Natural*, *Más Graves*, *Voces Claras*, *Acústico Cálido*, *Más Brillo*, *Noche*), Preamp y limitador suave anti-distorsión (`tanh`).
  - **Audio 8D orbital (sin reverb)**: pantalla dedicada `Spatial8dScreen` con detección automática de salida (`AudioDeviceCallback`): perfil binaural para **auriculares** (paneo orbital, micro-retardo ITD y sombra craneal) y perfil **mono-safe para altavoz** (sin cancelación de fase ni reverb) para usuarios sin auriculares, más control de velocidad e intensidad.
- **Cola fluida sin microcortes y editable (`QueueSheet`)**: Encolado incremental en `MediaController` (`addMediaItem`) sin interrumpir la canción actual, más reordenamiento *drag-and-drop* y eliminación directa en la cola.
- **Compuerta de permisos previos (`PermissionsScreen`)**: Antes de entrar a la app, solicita `POST_NOTIFICATIONS` (Android 13+) con `permission_handler` y explica el acceso privado a música y galería.
- **Motor nativo Media3 ExoPlayer (`AuraPlaybackService.kt`)**: Reproducción en segundo plano como `MediaSessionService`, Audio Focus automático, pausa al desconectar auriculares y controles en notificaciones / pantalla bloqueada.
- **Formatos soportados**: MP3, FLAC, WAV, AAC/M4A, OGG, OPUS, ALAC y WMA, con insignia técnica de bitrate y frecuencia de muestreo.
- **Edición de metadatos y carátula WebP sin pérdida (`EditTrackMetadataScreen` + `AuraArtworkProcessor.kt`)**: Permite editar título, artista, álbum y carpeta, así como elegir una carátula desde la galería (`image_picker`) que se convierte en segundo plano a **WebP con compresión máxima sin pérdida** (`WEBP_LOSSLESS` calidad `100` en Android 11+ / `WEBP` calidad `100` en Android 9–10).
- **Biblioteca instantánea con SQLite (`sqflite`)**: Hidratación diferida tras el primer frame, playlists locales, favoritos, álbumes, carpetas, búsqueda instantánea y cola interactiva.
- **Motor `yt-dlp` + `yt-dlp-ejs` auto-actualizable**:
  - **Auto-actualizador desde PyPI sin recompilar APK (`aura_yt_engine.py` + `AuraYtDownloader.kt`)**: Descarga *wheels* Python puros (`yt-dlp` y `yt-dlp-ejs`) hacia `filesDir/yt_dlp_updates/`, valida integridad **SHA-256** y protección **ZipSlip**, prioriza el directorio en `sys.path[0]` y recarga `sys.modules` en caliente (con opción para restaurar las versiones base incluidas en el APK). Incluye verificación automática cada 24 horas al descargar o actualización manual bajo demanda.
- **Pantalla dedicada de Configuración (`SettingsScreen`)**:
  - Selector de apariencia (**Claro**, **Oscuro** o **Sistema**, con Modo Claro *Acoustic Warmth* por defecto y Modo Oscuro *Acoustic Warmth Dark* mediante `AuraPalette` / `ThemeExtension`).
  - Inspector en vivo de versiones del motor (`yt-dlp`, `yt-dlp-ejs`, Python, Rust QuickJS-ng, Rust Lofty, Rust DSP `aura_dsp` y ABI del dispositivo), estadísticas y limpieza de caché de streaming (512 MB máx), y controles para buscar, aplicar o revertir actualizaciones.
- **Soporte obligatorio 32 y 64 bits**: Compilación nativa de Kotlin, Chaquopy y Rust (`cargo-ndk`) para `armeabi-v7a` y `arm64-v8a`, orientada a distribución directa (APK / Uptodown).

---

## Requisitos previos

### Para compilar la app móvil (`aura_music/`)
- **Flutter SDK** (canal `stable`, Dart `>=3.4.0 <4.0.0`)
- **Java 17** (Temurin / OpenJDK)
- **Python 3.11** en el host de compilación (requerido por Chaquopy)
- **Rust Toolchain** (`aarch64-linux-android`, `armv7-linux-androideabi`), **`cargo-ndk`** y **`libclang-dev`** (requerido por `rquickjs` bindgen)
- **Android SDK** (`compileSdk = 36`, `minSdk = 28`, NDK `28.2.13676358`)

### Para el wrapper web en raíz (`src/`)
- **Node.js 20+** y `npm`

---

## Compilación y uso

### 1. Compilar APKs desde GitHub Actions (sin PC)
El workflow `.github/workflows/build-debug-apk.yml` configura Java 17, Python 3.11, `libclang-dev`, Rust (`aarch64` + `armv7`), `cargo-ndk`, Android SDK/NDK 28.2 y Flutter, y genera **dos artifacts independientes**:
- `aura-music-debug-arm64-v8a` (`app-arm64-v8a-debug.apk`, 64 bits)
- `aura-music-debug-armeabi-v7a` (`app-armeabi-v7a-debug.apk`, 32 bits)

### 2. Compilar localmente (Flutter)
```bash
cd aura_music
flutter pub get

# APK Debug por arquitectura (recomendado con Chaquopy + cargo-ndk)
flutter build apk --debug --target-platform android-arm64
flutter build apk --debug --target-platform android-arm

# APK Release por arquitectura (Uptodown / distribución directa)
flutter build apk --release --target-platform android-arm64
flutter build apk --release --target-platform android-arm
```

### 3. Tests unitarios (Rust, Python y wrapper web)
```bash
# Tests unitarios de lógica Rust (URL parser, magic bytes, Lofty, Biquad DSP y limitador)
cd aura_music/rust/aura_yt_engine && cargo test
cd aura_music/rust/aura_dsp && cargo test

# Tests unitarios Python (auto-actualizador PyPI, búsqueda Explorar y resolución de streaming)
python3 -m unittest aura_music/test/python/test_aura_yt_engine.py -v

# Wrapper web (raíz)
npm install
npm run lint
npm run build
npx tsx --test src/appMeta.test.ts
```

---

## Documentación relacionada

- [`STRUCTURE.md`](./STRUCTURE.md): Árbol completo de archivos y responsabilidades.
- [`ROADMAP.md`](./ROADMAP.md): Estado actual y próximas fases del proyecto.
- [`AI_CONTEXT.md`](./AI_CONTEXT.md): Contexto técnico y decisiones de diseño para IA.
- [`AGENTS.md`](./AGENTS.md): Reglas de desarrollo para agentes que modifiquen este repo.
- [`README_AI.md`](./README_AI.md): Guía rápida de arranque para asistentes técnicos.
- [`aura_music/docs/ARCHITECTURE_RUST.md`](./aura_music/docs/ARCHITECTURE_RUST.md): Detalle de la arquitectura Rust (`aura_yt_engine` y `aura_dsp`).
