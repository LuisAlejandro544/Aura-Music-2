# Contexto Técnico para IA (`AI_CONTEXT.md`)

Este archivo resume las decisiones arquitectónicas, límites del entorno y flujos internos de **Aura Music** para que cualquier modelo de IA entienda el proyecto sin asumir comportamientos falsos.

---

## 1. Dos mundos dentro del mismo repositorio

1. **Aplicación real (`aura_music/`)**: App móvil Android escrita en **Flutter/Dart + Kotlin** (`minSdk = 28`, `targetSdk = 36`, ABIs `armeabi-v7a` y `arm64-v8a`).
2. **Wrapper web en raíz (`src/`)**: Aplicación React + Vite mínima que únicamente renderiza `"Hello World"` (`src/App.tsx`). Existe solo para el servidor web de previsualización en puerto 3000. **No implementa el reproductor ni debe confundirse con la app móvil.**
3. **Entorno de compilación**: En el contenedor local no hay Flutter/Android SDK; la compilación real de APKs ocurre en GitHub Actions (`.github/workflows/build-debug-apk.yml`) pensado para flujo sin PC desde teléfono.

---

## 2. Principios de arquitectura no negociables

1. **Privacidad por diseño (SAF sin escaneo global)**:
   - Prohibido añadir `READ_EXTERNAL_STORAGE` o `MANAGE_EXTERNAL_STORAGE`.
   - Toda importación pasa por `AuraSafImporter.kt` (`ACTION_OPEN_DOCUMENT` / `ACTION_OPEN_DOCUMENT_TREE`) con `takePersistableUriPermission`.
   - Las carátulas personalizadas usan `image_picker` (Photo Picker / selector del sistema), que tampoco requiere `READ_MEDIA_IMAGES`.
2. **Desacoplamiento del motor de audio (`AudioEnginePort`)**:
   - Las pantallas y `Provider`s solo hablan con `AudioEnginePort` (`lib/core/audio/audio_engine_port.dart`).
   - Hoy lo implementa `ExoPlayerBridge` (`com.auramusic.player/audio` y `/events`). En Fase 3 se conectará Rust (`aura_dsp`) detrás de este mismo contrato o mediante `AudioProcessor` en `AuraPlaybackService.kt`.
3. **Compuerta previa de permisos (`_PermissionsEntryGate` + `PermissionsScreen`)**:
   - `main.dart` evalúa `Permission.notification.status` y `SharedPreferences` antes de montar `AppShell`.
   - En Android 13+, `POST_NOTIFICATIONS` se solicita antes de entrar a la app; si el usuario lo deniega permanentemente, ofrece `openAppSettings()` y una salida controlada para no bloquear el uso.
4. **Concurrencia fuera del hilo principal**:
   - Extracción SAF (`AuraSafImporter.kt` + `AuraTrackMetadata.kt`): `Dispatchers.IO` con `Semaphore(4)`.
   - Conversión WebP de carátulas (`AuraArtworkProcessor.kt`): `Dispatchers.IO` con `ImageDecoder` (API 28+) y `Bitmap.recycle()`.
5. **Persistencia y protección de ediciones del usuario (`LibraryDatabase` v2)**:
   - SQLite guarda `originalArtworkPath` y `hasCustomMetadata`.
   - Si el usuario edita metadatos o fija una carátula WebP sin pérdida, los archivos se guardan en `filesDir/custom_artworks/` (no en `cacheDir`) y `LibraryProvider._runImport` respeta `hasCustomMetadata == true` al re-importar carpetas.
   - `PlayerProvider.syncUpdatedTrack` actualiza la cola en Dart y llama a `updateMediaItemMetadata` en Kotlin (`MediaController.replaceMediaItem`) para reflejar cambios en vivo en notificación y pantalla bloqueada.

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
  - Barra inferior custom `_AuraBottomBar` (`Inicio`, `Buscar`, `Biblioteca`) dentro de `app_shell.dart`, más `MiniPlayer` flotante y navegación por rutas a `FullPlayerScreen`, `CollectionDetailScreen` y `EditTrackMetadataScreen`.

---

## 4. Dependencias activas y licencias

Todas las librerías en `aura_music/pubspec.yaml` y `aura_music/android/app/build.gradle.kts` usan licencias permisivas (**MIT, BSD-2/3-Clause, Apache-2.0**):
- Flutter: `provider`, `sqflite`, `path_provider`, `path`, `shared_preferences`, `flutter_animate`, `permission_handler`, `image_picker`.
- Android: `androidx.media3:*` (`1.4.1`), `androidx.documentfile`, `kotlinx-coroutines-android`, `androidx.core:core-ktx`.
