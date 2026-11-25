# Guía Rápida de Arranque para IA (`README_AI.md`)

Lee este archivo primero cuando abras el repositorio en una nueva sesión para orientarte en menos de 60 segundos.

---

## 1. Dónde está cada cosa

| Necesitas trabajar en... | Ve directamente a... |
|---|---|
| Arranque, compuerta de permisos y providers | `aura_music/lib/main.dart`, `aura_music/lib/screens/permissions/permissions_screen.dart` |
| Navegación principal, barra inferior y MiniPlayer | `aura_music/lib/screens/app_shell.dart`, `aura_music/lib/widgets/mini_player.dart` |
| Pantallas principales y descarga por URL | `aura_music/lib/screens/{home,search,library,collection,player,metadata,import}/` |
| Estado de biblioteca, descargas, edición y SQLite | `aura_music/lib/state/library_provider.dart`, `aura_music/lib/core/storage/library_database.dart` |
| Estado de reproducción y puente Dart <-> Kotlin | `aura_music/lib/state/player_provider.dart`, `aura_music/lib/core/audio/` |
| Servicio ExoPlayer, SAF, WebP y puente `yt-dlp` | `aura_music/android/app/src/main/kotlin/com/auramusic/player/` |
| Motor Python mínimo (`yt-dlp` + `yt-dlp-ejs`) | `aura_music/android/app/src/main/python/aura_yt_engine.py` |
| Crate Rust (`QuickJS-ng` + `Lofty` + `JNI`) | `aura_music/rust/aura_yt_engine/Cargo.toml`, `src/lib.rs`, `src/bin/aura_qjs.rs` |
| Compilación APK 32/64 bits en GitHub | `.github/workflows/build-debug-apk.yml`, `aura_music/android/app/build.gradle.kts` |
| Vista web del contenedor (solo Hello World) | `src/App.tsx`, `package.json` |

---

## 2. Trampas conocidas que debes evitar

1. **No edites `src/App.tsx` pensando que es Aura Music**: La app real está en `aura_music/`. En el entorno web solo se compila el cascarón `src/` para pasar los checks de Vite/TypeScript.
2. **Chaquopy, `--split-per-abi` y ABIs en Debug**: Chaquopy no es compatible con `splits.abi` de AGP, y el plugin de Flutter suele inyectar `armeabi-v7a`, `arm64-v8a` y `x86_64` en compilaciones Debug. Conserva la guarda `if (!isSplitPerAbi)`, el bloque `androidComponents { finalizeDsl ... }` y `packaging.jniLibs.excludes` en `aura_music/android/app/build.gradle.kts`, así como la verificación por ABI en `.github/workflows/build-debug-apk.yml`.
3. **Ejecución de `libaura_qjs.so` en Android 10–16**: El binario CLI de QuickJS-ng (`aura_qjs`) debe copiarse a `jniLibs/<abi>/libaura_qjs.so` compilado con `-C link-arg=-Wl,-z,max-page-size=16384`, manteniendo `android:extractNativeLibs="true"` y `packaging.jniLibs.useLegacyPackaging = true`.
4. **`rquickjs` con `bindgen` en CI**: Requiere `libclang-dev` instalado en el runner de Ubuntu (`build-debug-apk.yml` ya lo instala antes de ejecutar Gradle/`cargo-ndk`).
5. **Almacenamiento de archivos y carátulas**:
   - Audio descargado desde URL -> `filesDir/downloads/`.
   - Carátulas extraídas automáticamente del audio -> `cacheDir/artworks/`.
   - Vista previa al editar -> `cacheDir/pending_artworks/`.
   - Carátula personalizada WebP (o de descarga) -> `filesDir/custom_artworks/` (persistente).
6. **Re-importación segura**: Nunca sobrescribas títulos, artistas, álbumes o carátulas cuando `AudioTrack.hasCustomMetadata == true`.
7. **Versiones de esquema SQLite**: `LibraryDatabase` está en `_dbVersion = 2`. Si agregas columnas nuevas en el futuro, incrementa `_dbVersion` y escribe `onUpgrade` idempotente (verificando `PRAGMA table_info(tracks)`).
8. **Pantallas estrechas (360 dp)**: En cabeceras con múltiples acciones o filas con insignias técnicas + botones, usa siempre `Expanded` / `Flexible` y `maxLines: 1, overflow: TextOverflow.ellipsis`.

---

## 3. Checklist rápido antes de cerrar una tarea

1. ¿Verificaste que no hay llamadas pesadas ni E/S en el hilo UI de Kotlin o Dart?
2. ¿Se mantiene compatibilidad con `minSdk = 28`, `armeabi-v7a` y `arm64-v8a`?
3. ¿Las nuevas dependencias en `pubspec.yaml`, `build.gradle.kts` o `Cargo.toml` evitan licencias GPL/AGPL?
4. ¿El wrapper web (`npm run build` / `npm run lint`) sigue compilando limpio?
5. ¿Los `.md` afectados (`README.md`, `ROADMAP.md`, `STRUCTURE.md`, `AI_CONTEXT.md`, `aura_music/docs/ARCHITECTURE_RUST.md`) reflejan los cambios?
