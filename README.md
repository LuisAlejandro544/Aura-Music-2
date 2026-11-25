# Aura Music

Reproductor de música local para **Android 9+ (`minSdk = 28`)** construido con **Flutter + Dart** y motor nativo **Media3 ExoPlayer** en Kotlin, diseñado con estética cálida (*Acoustic Warmth*), importación privada bajo demanda mediante **Storage Access Framework (SAF)** y arquitectura desacoplada lista para integrar procesamiento de audio DSP en **Rust**.

> **Nota sobre la estructura del repositorio:** La aplicación móvil real vive dentro de `aura_music/`. La raíz del repositorio contiene un wrapper web mínimo en React/Vite (`src/`) usado únicamente como vista de entorno web, además del workflow de compilación en `.github/workflows/build-debug-apk.yml`.

---

## Características principales

- **Importación privada sin escaneo global**: Nunca solicita `READ_EXTERNAL_STORAGE` ni `MANAGE_EXTERNAL_STORAGE`. El usuario elige explícitamente canciones o carpetas mediante SAF (`AuraSafImporter.kt`) con permisos persistentes.
- **Compuerta de permisos previos (`PermissionsScreen`)**: Antes de entrar a la app, solicita `POST_NOTIFICATIONS` (Android 13+) con `permission_handler` y explica el acceso privado a música y galería.
- **Motor nativo Media3 ExoPlayer (`AuraPlaybackService.kt`)**: Reproducción en segundo plano como `MediaSessionService`, Audio Focus automático, pausa al desconectar auriculares y controles en notificaciones / pantalla bloqueada.
- **Formatos soportados**: MP3, FLAC, WAV, AAC/M4A, OGG, OPUS, ALAC y WMA, con insignia técnica de bitrate y frecuencia de muestreo.
- **Edición de metadatos y carátula WebP sin pérdida (`EditTrackMetadataScreen` + `AuraArtworkProcessor.kt`)**: Permite editar título, artista, álbum y carpeta, así como elegir una carátula desde la galería (`image_picker`) que se convierte en segundo plano a **WebP con compresión máxima sin pérdida** (`WEBP_LOSSLESS` calidad `100` en Android 11+ / `WEBP` calidad `100` en Android 9–10).
- **Biblioteca instantánea con SQLite (`sqflite`)**: Hidratación diferida tras el primer frame, playlists locales, favoritos, álbumes, carpetas, búsqueda instantánea y cola interactiva.
- **Soporte 32 y 64 bits**: Compilación directa para `armeabi-v7a` y `arm64-v8a` orientada a distribución directa (APK / Uptodown).

---

## Requisitos previos

### Para compilar la app móvil (`aura_music/`)
- **Flutter SDK** (canal `stable`, Dart `>=3.4.0 <4.0.0`)
- **Java 17** (Temurin / OpenJDK)
- **Android SDK** (`compileSdk = 36`, `minSdk = 28`, NDK `28.2.13676358`)

### Para el wrapper web en raíz (`src/`)
- **Node.js 20+** y `npm`

---

## Compilación y uso

### 1. Compilar APKs desde GitHub Actions (sin PC)
El workflow `.github/workflows/build-debug-apk.yml` se ejecuta al hacer push a `main`/`master` o de forma manual (`workflow_dispatch`) y genera **dos artifacts independientes**:
- `aura-music-debug-arm64-v8a` (`app-arm64-v8a-debug.apk`, 64 bits)
- `aura-music-debug-armeabi-v7a` (`app-armeabi-v7a-debug.apk`, 32 bits)

### 2. Compilar localmente (Flutter)
```bash
cd aura_music
flutter pub get

# APK Debug separado por arquitectura
flutter build apk --debug --split-per-abi --target-platform android-arm,android-arm64

# APK Release separado por arquitectura (Uptodown / distribución directa)
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

### 3. Tests del wrapper web (raíz)
```bash
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
- [`aura_music/docs/ARCHITECTURE_RUST.md`](./aura_music/docs/ARCHITECTURE_RUST.md): Detalle de la arquitectura de audio y ruta hacia Rust DSP.
