# Estructura del Proyecto

Árbol completo del repositorio y responsabilidad de cada directorio y archivo.

```text
/
├── .github/
│   └── workflows/
│       └── build-debug-apk.yml      # GitHub Action: compila APKs Debug por ABI (arm64-v8a y armeabi-v7a) y detecta Rust
├── aura_music/                      # Proyecto principal de la app móvil Android (Flutter + Kotlin)
│   ├── pubspec.yaml                 # Dependencias Dart/Flutter (todas con licencias permisivas MIT/BSD/Apache-2.0)
│   ├── docs/
│   │   └── ARCHITECTURE_RUST.md     # Arquitectura de audio actual y guía de acoplamiento con Rust DSP
│   ├── android/
│   │   ├── build.gradle.kts         # Configuración raíz de Gradle y repositorios
│   │   ├── gradle.properties        # Memoria JVM, AndroidX y compatibilidad de plugins
│   │   ├── settings.gradle.kts      # Carga del SDK Flutter y versiones de AGP/Kotlin
│   │   └── app/
│   │       ├── build.gradle.kts     # minSdk 28, targetSdk 36, Media3 ExoPlayer, Coroutines y soporte ABI 32/64 bits
│   │       ├── proguard-rules.pro   # Reglas R8/ProGuard para conservar Media3 y el puente nativo
│   │       └── src/main/
│   │           ├── AndroidManifest.xml
│   │           ├── kotlin/com/auramusic/player/
│   │           │   ├── MainActivity.kt          # Registra AuraAudioBridge y delega resultados de Activity
│   │           │   ├── AuraAudioBridge.kt       # MethodChannel + EventChannel entre Flutter, ExoPlayer, SAF y WebP
│   │           │   ├── AuraPlaybackService.kt   # MediaSessionService con ExoPlayer, Audio Focus y notificaciones
│   │           │   ├── AuraSafImporter.kt       # Selector SAF (archivos/carpetas) con permisos persistentes y Semaphore(4)
│   │           │   ├── AuraTrackMetadata.kt     # Extractor de etiquetas ID3/Vorbis/MP4 y carátulas incrustadas en IO
│   │           │   └── AuraArtworkProcessor.kt  # Conversión nativa de galería a WebP máxima compresión sin pérdida
│   │           └── res/
│   │               ├── drawable/ic_launcher_foreground.xml
│   │               ├── drawable/launch_background.xml
│   │               ├── mipmap-anydpi-v26/ic_launcher.xml
│   │               └── values/styles.xml        # Tema claro de arranque (#F9F6F0) sin destellos negros
│   └── lib/
│       ├── main.dart                # Inicializa providers, difiere hidratación y muestra compuerta de permisos
│       ├── core/
│       │   ├── audio/
│       │   │   ├── audio_engine_port.dart       # Contrato abstracto del motor (permite migrar/acoplar Rust)
│       │   │   └── exoplayer_bridge.dart        # Implementación concreta sobre MethodChannel/EventChannel
│       │   ├── models/
│       │   │   └── audio_track.dart             # Modelos inmutables (AudioTrack, LocalCollection, LosslessWebpResult)
│       │   ├── storage/
│       │   │   └── library_database.dart        # Persistencia SQLite (v2) de pistas, playlists y ediciones propias
│       │   ├── theme/
│       │   │   └── aura_theme.dart              # Paleta "Acoustic Warmth", ThemeData y tintes por semilla
│       │   └── utils/
│       │       └── duration_format.dart         # Formateo de duraciones (mm:ss, h:mm:ss y resúmenes)
│       ├── state/
│       │   ├── library_provider.dart            # Estado de catálogo, álbumes, carpetas, playlists, importación y edición
│       │   └── player_provider.dart             # Estado de cola, reproducción, scrub, shuffle, repeat y reanudación
│       ├── screens/
│       │   ├── app_shell.dart                   # Contenedor con IndexedStack, MiniPlayer y _AuraBottomBar
│       │   ├── permissions/
│       │   │   └── permissions_screen.dart      # Pantalla previa de solicitud/confirmación de permisos
│       │   ├── home/
│       │   │   └── home_screen.dart             # Inicio: accesos rápidos 2x2, recién importado, álbumes y recientes
│       │   ├── search/
│       │   │   └── search_screen.dart           # Búsqueda instantánea local y filtros (Todo, Lossless, Favoritos)
│       │   ├── library/
│       │   │   └── library_screen.dart          # Canciones, Álbumes, Carpetas, Playlists y creación/ordenamiento
│       │   ├── collection/
│       │   │   └── collection_detail_screen.dart # Vista dedicada de álbum, carpeta o playlist
│       │   ├── player/
│       │   │   └── full_player_screen.dart      # Reproductor completo con gestos verticales/horizontales y barra técnica
│       │   └── metadata/
│       │       └── edit_track_metadata_screen.dart # Editor de etiquetas y selector de carátula WebP sin pérdida
│       └── widgets/
│           ├── artwork_view.dart                # Renderizador optimizado de carátulas (cacheWidth) + disco fallback
│           ├── mini_player.dart                 # Mini reproductor flotante con swipe y progreso en vivo
│           ├── track_tile.dart                  # Fila de pista reutilizable con insignia de formato
│           └── sheets/
│               ├── import_source_sheet.dart     # Popup de importación SAF (archivos o carpeta) con progreso
│               ├── queue_sheet.dart             # Popup de cola de reproducción activa
│               └── track_options_sheet.dart     # Popup contextual (favorito, cola, playlist, editar, ficha técnica)
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
