# Estructura del Proyecto

Árbol completo del repositorio y responsabilidad de cada directorio y archivo.

```text
/
├── .github/
│   └── workflows/
│       └── build-debug-apk.yml      # GitHub Action: configura Java 17, Python 3.11, Rust + cargo-ndk y compila APKs por ABI (arm64-v8a y armeabi-v7a)
├── aura_music/                      # Proyecto principal de la app móvil Android (Flutter + Kotlin + Rust + Chaquopy)
│   ├── pubspec.yaml                 # Dependencias Dart/Flutter (todas con licencias permisivas MIT/BSD/Apache-2.0)
│   ├── docs/
│   │   └── ARCHITECTURE_RUST.md     # Arquitectura de audio, motor yt-dlp + QuickJS-ng en Rust y motor DSP (aura_dsp)
│   ├── rust/
│   │   ├── aura_yt_engine/          # Crate nativo Rust (MIT/Apache-2.0) compilado vía cargo-ndk en 32 y 64 bits
│   │   │   ├── Cargo.toml           # Dependencias: rquickjs 0.14, lofty 0.22, jni 0.21, serde, serde_json
│   │   │   └── src/
│   │   │       ├── lib.rs           # JNI libaura_yt_rust.so: canonicalización de URLs, magic bytes y tagging Lofty
│   │   │       └── bin/
│   │   │           └── aura_qjs.rs  # Binario libaura_qjs.so: runtime QuickJS-ng para resolver retos JS de yt-dlp-ejs
│   │   └── aura_dsp/                # Crate DSP nativo Rust (MIT/Apache-2.0) para ecualización en tiempo real
│   │       ├── Cargo.toml           # Dependencias: jni 0.21, serde, serde_json
│   │       └── src/
│   │           └── lib.rs           # JNI libaura_dsp.so: Biquad IIR 5 bandas, Preamp y limitador soft-knee tanh
│   ├── android/
│   │   ├── build.gradle.kts         # Configuración raíz de Gradle y repositorios
│   │   ├── gradle.properties        # Memoria JVM, AndroidX y configuration-cache=false (requerido por Chaquopy)
│   │   ├── settings.gradle.kts      # Carga del SDK Flutter, AGP, Kotlin y plugin com.chaquo.python 17.2.0
│   │   └── app/
│   │       ├── build.gradle.kts     # minSdk 28, targetSdk 36, Media3 ExoPlayer, Chaquopy 3.11, cargo-ndk (yt_engine + dsp) y aislamiento por ABI
│   │       ├── proguard-rules.pro   # Reglas R8/ProGuard para conservar Media3, Chaquopy y el puente nativo/JNI
│   │       └── src/main/
│   │           ├── AndroidManifest.xml          # Permisos (INTERNET, FOREGROUND_SERVICE_MEDIA_PLAYBACK, etc.) y extractNativeLibs=true
│   │           ├── python/
│   │           │   └── aura_yt_engine.py        # Orquestador Python (yt-dlp + yt-dlp-ejs + QuickJS-ng + certifi) y auto-actualizador PyPI (SHA-256 / ZipSlip / hot-reload)
│   │           ├── kotlin/com/auramusic/player/
│   │           │   ├── MainActivity.kt          # Registra AuraAudioBridge y delega resultados de Activity
│   │           │   ├── AuraAudioBridge.kt       # MethodChannel + EventChannel: MediaController incremental, limpieza física, DSP, SAF, WebP y auto-actualizador yt-dlp
│   │           │   ├── AuraPlaybackService.kt   # MediaSessionService con ExoPlayer, DefaultAudioSink + AuraRustDspProcessor y Audio Focus
│   │           │   ├── AuraRustDspBridge.kt     # Puente JNI hacia libaura_dsp.so y persistencia de ecualizador en SharedPreferences
│   │           │   ├── AuraRustDspProcessor.kt  # AudioProcessor Media3 que procesa DirectByteBuffer PCM en Rust aura_dsp
│   │           │   ├── AuraSafImporter.kt       # Selector SAF (archivos/carpetas) con permisos persistentes y Semaphore(4)
│   │           │   ├── AuraTrackMetadata.kt     # Extractor de etiquetas ID3/Vorbis/MP4 y carátulas incrustadas en IO
│   │           │   ├── AuraArtworkProcessor.kt  # Conversión nativa de galería/miniaturas a WebP máxima compresión sin pérdida
│   │           │   ├── AuraRustYtBridge.kt      # Puente JNI hacia libaura_yt_rust.so y ruta a libaura_qjs.so
│   │           │   └── AuraYtDownloader.kt      # Descargador y gestor de actualizaciones PyPI en Dispatchers.IO con Mutex y chequeo cada 24 h
│   │           └── res/
│   │               ├── drawable/ic_launcher_foreground.xml
│   │               ├── drawable/launch_background.xml
│   │               ├── mipmap-anydpi-v26/ic_launcher.xml
│   │               └── values/styles.xml        # Tema claro de arranque (#F9F6F0) sin destellos negros
│   ├── test/
│   │   └── python/
│   │       └── test_aura_yt_engine.py # Tests unitarios del auto-actualizador Python (versiones, SHA-256, ZipSlip y recarga)
│   └── lib/
│       ├── main.dart                # Inicializa providers (incluido SettingsProvider), aplica tema Claro/Oscuro y compuerta de permisos
│       ├── core/
│       │   ├── audio/
│       │   │   ├── audio_engine_port.dart       # Contrato abstracto del motor (reproducción, cola incremental, DSP, SAF, WebP, yt-dlp y actualizaciones)
│       │   │   └── exoplayer_bridge.dart        # Implementación concreta sobre MethodChannel/EventChannel
│       │   ├── models/
│       │   │   └── audio_track.dart             # Modelos (AudioTrack, LocalCollection, EqualizerState, YtEngineStatus, YtUpdateCheckResult, etc.)
│       │   ├── storage/
│       │   │   └── library_database.dart        # Persistencia SQLite (v2) de pistas, playlists y ediciones propias
│       │   ├── theme/
│       │   │   └── aura_theme.dart              # Paleta "Acoustic Warmth" Claro/Oscuro (AuraPalette ThemeExtension) y tintes por semilla
│       │   └── utils/
│       │       └── duration_format.dart         # Formateo de duraciones (mm:ss, h:mm:ss y resúmenes)
│       ├── state/
│       │   ├── library_provider.dart            # Estado de catálogo, importación SAF, descargas yt-dlp, limpieza de recursos y playlists
│       │   ├── player_provider.dart             # Estado de cola editable sin microcortes, DSP/Ecualizador, reproducción y reanudación
│       │   └── settings_provider.dart           # Estado de Configuración: ThemeMode persistente, versiones del motor y control de auto-actualizador
│       ├── screens/
│       │   ├── app_shell.dart                   # Contenedor con IndexedStack, MiniPlayer y _AuraBottomBar
│       │   ├── permissions/
│       │   │   └── permissions_screen.dart      # Pantalla previa de solicitud/confirmación de permisos
│       │   ├── home/
│       │   │   └── home_screen.dart             # Inicio: accesos rápidos 2x2, acceso a Configuración, recién importado, álbumes y recientes
│       │   ├── search/
│       │   │   └── search_screen.dart           # Búsqueda instantánea local y filtros (Todo, Lossless, Favoritos)
│       │   ├── library/
│       │   │   └── library_screen.dart          # Canciones, Álbumes, Carpetas, Playlists y creación/ordenamiento
│       │   ├── collection/
│       │   │   └── collection_detail_screen.dart # Vista dedicada de álbum, carpeta o playlist
│       │   ├── player/
│       │   │   └── full_player_screen.dart      # Reproductor completo con gestos, acceso a cola y ecualizador Rust
│       │   ├── equalizer/
│       │   │   └── equalizer_screen.dart        # Pantalla dedicada y accesible del Ecualizador DSP en Rust (curva, perfiles y 5 bandas)
│       │   ├── metadata/
│       │   │   └── edit_track_metadata_screen.dart # Editor de etiquetas y selector de carátula WebP sin pérdida
│       │   ├── import/
│       │   │   └── download_url_screen.dart     # Pantalla dedicada de descarga de audio desde URL (yt-dlp + QuickJS Rust)
│       │   └── settings/
│       │       └── settings_screen.dart         # Pantalla de Configuración: Modo Claro/Oscuro/Sistema, versiones en vivo y auto-actualizador yt-dlp
│       └── widgets/
│           ├── artwork_view.dart                # Renderizador optimizado de carátulas (cacheWidth) + disco fallback
│           ├── mini_player.dart                 # Mini reproductor flotante con swipe y progreso en vivo
│           ├── track_tile.dart                  # Fila de pista reutilizable con insignia de formato
│           └── sheets/
│               ├── import_source_sheet.dart     # Popup de importación (archivos SAF, carpeta SAF o descarga desde URL)
│               ├── queue_sheet.dart             # Popup de cola interactiva (drag-and-drop para reordenar y quitar pistas)
│               └── track_options_sheet.dart     # Popup contextual (favorito, cola, playlist, ecualizador, editar, ficha técnica)
├── src/                             # Wrapper web mínimo (Hello World) para vista previa del entorno web
│   ├── App.tsx
│   ├── appMeta.ts
│   ├── appMeta.test.ts
│   ├── index.css
│   └── main.tsx
├── index.html
├── metadata.json
├── package.json
├── tsconfig.json
├── vite.config.ts
├── README.md
├── ROADMAP.md
├── STRUCTURE.md
├── AI_CONTEXT.md
├── AGENTS.md
└── README_AI.md
```
