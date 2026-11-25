# Reglas para Agentes de Código (`AGENTS.md`)

Cualquier agente o desarrollador asistido por IA que trabaje en este repositorio debe cumplir estas reglas estrictamente:

---

## 1. Prioridades del producto y distribución
- **Distribución fuera de Google Play**: El APK está orientado a distribución directa / Uptodown. No asumas servicios exclusivos de Play Store ni cambies `applicationId` sin autorización.
- **Usuario móvil sin PC**: La compilación y descarga de pruebas ocurre desde el teléfono usando `.github/workflows/build-debug-apk.yml`. Mantén el workflow funcional, con caché activa y artifacts separados por arquitectura (`aura-music-debug-arm64-v8a` y `aura-music-debug-armeabi-v7a`).
- **32 y 64 bits obligatorios**: Cualquier código nativo (Kotlin, JNI, NDK o futuro Rust) debe compilar y probarse para `armeabi-v7a` y `arm64-v8a`, respetando `minSdk = 28` (Android 9+). En `aura_music/android/app/build.gradle.kts`, conserva la guarda `isSplitPerAbi` para no chocar con `--split-per-abi`.

## 2. Reglas de código y dependencias
- **Usa dependencias reales y probadas**: No improvises soluciones caseras frágiles cuando exista un paquete sólido, pero verifica siempre la licencia.
- **Prohibidas licencias virales o con atribución obligatoria restrictiva**: No añadas dependencias GPL, AGPL ni librerías que obliguen a liberar el código fuente del proyecto o exigir créditos en UI. Solo MIT, BSD o Apache-2.0.
- **Evita marcas registradas en nombres de archivos o clases**: No uses nombres comerciales protegidos por derechos de autor en archivos, paquetes o identificadores.
- **No uses `persist.sys.*`** en ninguna lógica Android.
- **Coroutines obligatorias en Kotlin**: Toda operación de E/S, SAF, SQLite o decodificación/compresión de imágenes (`ImageDecoder`, `MediaMetadataRetriever`, WebP) debe ejecutarse en `Dispatchers.IO`, nunca en el hilo principal.
- **Sin fallbacks que oculten tecnología pedida**: Cuando se integre Rust (`aura_music/rust/`), debe compilarse en Gradle (`cargo-ndk`) para 32 y 64 bits sin sustituirlo por fallbacks falsos en Kotlin.
- **Comentarios explicativos en código**: Todo archivo nuevo o modificado debe incluir cabecera clara explicando qué lógica contiene y para qué sirve.

## 3. Reglas de UI/UX y modularidad
- **No cambies diseño, colores ni iconos** salvo que el usuario lo pida explícitamente o estés corrigiendo un error visual concreto (como desbordamientos).
- **Evita el minimalismo extremo o pantallas saturadas**: Usa pantallas separadas (`PermissionsScreen`, `CollectionDetailScreen`, `FullPlayerScreen`, `EditTrackMetadataScreen`) y popups/sheets (`ImportSourceSheet`, `QueueSheet`, `TrackOptionsSheet`) en lugar de amontonar formularios en una sola vista.
- **No toques lógica funcional ajena al cambio pedido**: Cambios innecesarios en servicios o bridges pueden romper la reproducción en dispositivos reales.

## 4. Documentación y control de cambios
- Si modificas arquitectura, permisos, dependencias o el workflow de compilación, actualiza `README.md`, `STRUCTURE.md`, `AI_CONTEXT.md` y `aura_music/docs/ARCHITECTURE_RUST.md` para mantener la documentación sincronizada.
- Si existiera `commit_message.txt`, mantenlo en español y no lo modifiques a menos que el usuario lo pida.
