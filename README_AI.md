# Guía Rápida de Arranque para IA (`README_AI.md`)

Lee este archivo primero cuando abras el repositorio en una nueva sesión para orientarte en menos de 60 segundos.

---

## 1. Dónde está cada cosa

| Necesitas trabajar en... | Ve directamente a... |
|---|---|
| Arranque, compuerta de permisos y providers | `aura_music/lib/main.dart`, `aura_music/lib/screens/permissions/permissions_screen.dart` |
| Navegación principal, barra inferior y MiniPlayer | `aura_music/lib/screens/app_shell.dart`, `aura_music/lib/widgets/mini_player.dart` |
| Pantallas principales | `aura_music/lib/screens/{home,search,library,collection,player,metadata}/` |
| Estado de biblioteca, edición y SQLite | `aura_music/lib/state/library_provider.dart`, `aura_music/lib/core/storage/library_database.dart` |
| Estado de reproducción y puente Dart <-> Kotlin | `aura_music/lib/state/player_provider.dart`, `aura_music/lib/core/audio/` |
| Servicio ExoPlayer, SAF, metadatos y WebP nativo | `aura_music/android/app/src/main/kotlin/com/auramusic/player/` |
| Compilación APK 32/64 bits en GitHub | `.github/workflows/build-debug-apk.yml`, `aura_music/android/app/build.gradle.kts` |
| Vista web del contenedor (solo Hello World) | `src/App.tsx`, `package.json` |

---

## 2. Trampas conocidas que debes evitar

1. **No edites `src/App.tsx` pensando que es Aura Music**: La app real está en `aura_music/`. En el entorno web solo se compila el cascarón `src/` para pasar los checks de Vite/TypeScript.
2. **No combines `defaultConfig.ndk.abiFilters` sin la guarda `isSplitPerAbi`**: El workflow usa `flutter build apk --debug --split-per-abi`. En `aura_music/android/app/build.gradle.kts` ya existe `if (!isSplitPerAbi)` para evitar el error de conflicto con `splits.abi` de AGP.
3. **Almacenamiento de carátulas**:
   - Carátulas extraídas automáticamente del audio -> `cacheDir/artworks/`.
   - Vista previa al editar -> `cacheDir/pending_artworks/`.
   - Carátula personalizada WebP guardada por el usuario -> `filesDir/custom_artworks/` (persistente).
4. **Re-importación segura**: Nunca sobrescribas títulos, artistas, álbumes o carátulas cuando `AudioTrack.hasCustomMetadata == true`.
5. **Versiones de esquema SQLite**: `LibraryDatabase` está en `_dbVersion = 2`. Si agregas columnas nuevas en el futuro, incrementa `_dbVersion` y escribe `onUpgrade` idempotente (verificando `PRAGMA table_info(tracks)`).
6. **Pantallas estrechas (360 dp)**: En cabeceras con múltiples acciones o filas con insignias técnicas + botones, usa siempre `Expanded` / `Flexible` y `maxLines: 1, overflow: TextOverflow.ellipsis` para evitar franjas amarillas de `OVERFLOWED BY X PIXELS`.

---

## 3. Checklist rápido antes de cerrar una tarea

1. ¿Verificaste que no hay llamadas pesadas ni E/S en el hilo UI de Kotlin o Dart?
2. ¿Se mantiene compatibilidad con `minSdk = 28`, `armeabi-v7a` y `arm64-v8a`?
3. ¿Las nuevas dependencias en `pubspec.yaml` o `build.gradle.kts` tienen licencia permisiva (MIT/BSD/Apache-2.0)?
4. ¿El wrapper web (`npm run build` / `npm run lint`) sigue compilando limpio?
5. ¿Los `.md` afectados (`README.md`, `ROADMAP.md`, `STRUCTURE.md`, `AI_CONTEXT.md`, `aura_music/docs/ARCHITECTURE_RUST.md`) reflejan los cambios?
