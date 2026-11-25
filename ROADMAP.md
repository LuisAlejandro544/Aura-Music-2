# Roadmap de Aura Music

Este documento describe las etapas de evolución de **Aura Music**, desde la base actual en Flutter + Media3 ExoPlayer hasta la integración del motor DSP nativo en Rust.

---

## Fase 1 — Base funcional y experiencia local (Completada)

- [x] **Diseño *Acoustic Warmth* en modo claro** (`#F9F6F0`, `#F0EBE1`, `#2C2524`, `#D96B43`, `#E5A93B`, `#3B8A6E`).
- [x] **Navegación multipantalla modular**: `Inicio`, `Buscar`, `Biblioteca` (Canciones, Álbumes, Carpetas, Playlists), `CollectionDetailScreen`, `FullPlayerScreen`, `MiniPlayer` con gestos y hojas modales (`ImportSourceSheet`, `QueueSheet`, `TrackOptionsSheet`).
- [x] **Motor de reproducción nativo**: `AuraPlaybackService.kt` con `Media3 ExoPlayer` + `MediaSessionService`, Audio Focus, pausa al desconectar auriculares y controles en notificación/pantalla bloqueada.
- [x] **Importación privada vía SAF (`AuraSafImporter.kt`)**: Selección explícita de archivos/carpetas con `takePersistableUriPermission` y extracción paralela de metadatos en `Dispatchers.IO`.
- [x] **Persistencia rápida en SQLite (`LibraryDatabase` v2)**: Arranque inmediato con hidratación posterior al primer frame.
- [x] **Compuerta de permisos previos (`PermissionsScreen`)**: Solicitud de `POST_NOTIFICATIONS` antes de entrar a la app.
- [x] **Editor de metadatos y carátula WebP sin pérdida**: `EditTrackMetadataScreen` + `AuraArtworkProcessor.kt` con selección de galería (`image_picker`) y conversión a WebP de compresión máxima sin pérdida en `filesDir/custom_artworks/`.
- [x] **CI/CD móvil en GitHub Actions**: Workflow `build-debug-apk.yml` con artifacts independientes por arquitectura (`arm64-v8a` y `armeabi-v7a`).

---

## Fase 2 — Estabilidad nativa, cola fluida y distribución Release (Próxima)

- [ ] **Edición de cola sin microcortes**: Reemplazar el uso de `setQueueAndPlay` en `addToQueueEnd` / `playNextInQueue` por inserción incremental en `MediaController` (`addMediaItem(index, item)`).
- [ ] **Contador atómico en importación SAF**: Sustituir `var processed = 0` por `AtomicInteger` en `AuraSafImporter.kt` para garantizar progreso exacto bajo concurrencia.
- [ ] **Detección y limpieza de URIs revocadas o archivos movidos**: Verificar permisos SAF persistentes al reproducir y ofrecer re-vincular o limpiar referencias huérfanas.
- [ ] **Suite de tests automatizados en Flutter/Dart**: Pruebas unitarias y de widgets para `LibraryProvider`, `PlayerProvider`, `LibraryDatabase` y pantallas principales.
- [ ] **Reordenar y eliminar pistas dentro de `QueueSheet` y playlists**: Soporte drag-and-drop y edición de orden persistente.
- [ ] **Perfil de firma Release (`key.properties`) y workflow de APK Release**: Preparar publicación directa en Uptodown con APKs firmados por arquitectura (`--split-per-abi`).

---

## Fase 3 — Motor DSP nativo en Rust (`aura_dsp`)

- [ ] **Crate `aura_music/rust/` (`aura_dsp`)**: Implementación en Rust con licencias permisivas (MIT / Apache-2.0).
- [ ] **Ecualizador paramétrico Biquad multibanda**: Procesamiento en tiempo real sobre buffers PCM mediante `AudioProcessor` de Media3 por JNI o `flutter_rust_bridge`.
- [ ] **Normalización ReplayGain / LUFS**: Cálculo y aplicación de ganancia sin distorsión ni clipping.
- [ ] **Análisis espectral FFT en vivo**: Datos de espectro de baja latencia para visualizador reactivo en `FullPlayerScreen`.
- [ ] **Compilación automática con `cargo-ndk`**: Integrada en Gradle y GitHub Actions para `armeabi-v7a` (32 bits) y `arm64-v8a` (64 bits).
