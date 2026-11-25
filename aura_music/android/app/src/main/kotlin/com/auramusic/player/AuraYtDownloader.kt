// =============================================================================
// AuraYtDownloader.kt — Orquestador Kotlin de descarga con yt-dlp + Rust
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Ejecuta todo el pipeline de descarga desde URL en Dispatchers.IO sin
//   bloquear jamás la UI:
//   1. Valida y limpia la URL en Rust (`AuraRustYtBridge.parseMediaUrl`).
//   2. Inicia el entorno Python minimalista de Chaquopy (`yt-dlp --no-deps`,
//      `yt-dlp-ejs --no-deps`, `certifi`) de forma diferida al primer uso.
//   3. Ejecuta `aura_yt_engine.download_audio` pasando la ruta ejecutable de
//      `libaura_qjs.so` (Rust QuickJS-ng) para resolver desafíos JS de YouTube.
//   4. Convierte la carátula descargada a WebP sin pérdida persistente mediante
//      `AuraArtworkProcessor` en `filesDir/custom_artworks/`.
//   5. Verifica integridad del audio, lee bitrate/sampleRate/duración e
//      incrusta metadatos + portada en Rust (`AuraRustYtBridge.verifyAndTagAudio`
//      con `lofty`), devolviendo un `AuraTrackMetadata` listo para ExoPlayer.
// =============================================================================

package com.auramusic.player

import android.content.Context
import android.net.Uri
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest

interface YtProgressCallback {
    fun onProgress(
        stage: String,
        percent: Double,
        downloadedBytes: Long,
        totalBytes: Long,
        message: String
    )
}

class YtDownloadDetailedException(
    val summary: String,
    val rawDetail: String
) : IllegalStateException(summary)

object AuraYtDownloader {

    private const val DOWNLOADS_DIR = "aura_downloads"
    private const val YT_CACHE_DIR = "yt_dlp_cache"
    private const val YT_UPDATES_DIR = "yt_dlp_updates"

    private val pythonInitLock = Any()

    private fun ensurePythonStarted(context: Context): Python {
        val appContext = context.applicationContext
        synchronized(pythonInitLock) {
            if (!Python.isStarted()) {
                Python.start(AndroidPlatform(appContext))
            }
            return Python.getInstance()
        }
    }

    suspend fun getEngineStatus(context: Context): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            val appContext = context.applicationContext
            val rustInfo = AuraRustYtBridge.getEngineInfoJson(appContext)
            val pythonStarted = Python.isStarted()

            if (!pythonStarted) {
                return@withContext mapOf(
                    "pythonStarted" to false,
                    "pythonVersion" to "",
                    "ytDlpVersion" to "",
                    "ejsVersion" to "",
                    "quickjsBinaryPath" to rustInfo.optString("quickjsBinaryPath", ""),
                    "quickjsReady" to rustInfo.optBoolean("quickjsBinaryExists", false),
                    "rustCrate" to rustInfo.optString("rustCrate", ""),
                    "audioProcessor" to rustInfo.optString("audioProcessor", ""),
                    "arch" to rustInfo.optString("arch", "")
                )
            }

            val py = ensurePythonStarted(appContext)
            val module = py.getModule("aura_yt_engine")
            val qjsPath = AuraRustYtBridge.getQuickJsBinaryPath(appContext)
            val updateDir = File(appContext.filesDir, YT_UPDATES_DIR).absolutePath
            val pyJson = JSONObject(module.callAttr("get_engine_info", qjsPath, updateDir).toString())

            mapOf(
                "pythonStarted" to true,
                "pythonVersion" to pyJson.optString("pythonVersion", ""),
                "ytDlpVersion" to pyJson.optString("ytDlpVersion", ""),
                "ejsVersion" to pyJson.optString("ejsVersion", ""),
                "quickjsBinaryPath" to rustInfo.optString("quickjsBinaryPath", ""),
                "quickjsReady" to rustInfo.optBoolean("quickjsBinaryExists", false),
                "rustCrate" to rustInfo.optString("rustCrate", ""),
                "audioProcessor" to rustInfo.optString("audioProcessor", ""),
                "arch" to rustInfo.optString("arch", "")
            )
        }

    suspend fun downloadTrackFromUrl(
        context: Context,
        rawUrl: String,
        formatPref: String,
        onProgress: (stage: String, percent: Double, downloadedBytes: Long, totalBytes: Long, message: String) -> Unit
    ): AuraTrackMetadata = withContext(Dispatchers.IO) {
        val appContext = context.applicationContext

        onProgress("rust_url", 0.0, 0L, 0L, "Validando enlace con Rust...")
        val parsed = AuraRustYtBridge.parseMediaUrl(rawUrl)
        if (!parsed.valid || parsed.canonicalUrl.isBlank()) {
            val summary = parsed.error ?: "Enlace inválido"
            throw YtDownloadDetailedException(
                summary = summary,
                rawDetail = "Stage: rust_url\nInput URL: $rawUrl\nError: $summary"
            )
        }

        val quickJsPath = AuraRustYtBridge.getQuickJsBinaryPath(appContext)
        val qjsFile = File(quickJsPath)
        if (!qjsFile.exists()) {
            val msg = "No se encontró el binario nativo Rust QuickJS-ng en ${qjsFile.absolutePath}"
            throw YtDownloadDetailedException(
                summary = msg,
                rawDetail = "Stage: quickjs_check\nExpected binary: ${qjsFile.absolutePath}\nExists: false"
            )
        }

        val downloadsDir = File(appContext.filesDir, DOWNLOADS_DIR).apply {
            if (!exists()) mkdirs()
        }
        val cacheDir = File(appContext.cacheDir, YT_CACHE_DIR).apply {
            if (!exists()) mkdirs()
        }
        val updateDir = File(appContext.filesDir, YT_UPDATES_DIR).apply {
            if (!exists()) mkdirs()
        }

        onProgress("python_init", 2.0, 0L, 0L, "Iniciando intérprete Python minimalista...")
        val rawResult = try {
            val py = ensurePythonStarted(appContext)
            val module = py.getModule("aura_yt_engine")

            val callback = object : YtProgressCallback {
                override fun onProgress(
                    stage: String,
                    percent: Double,
                    downloadedBytes: Long,
                    totalBytes: Long,
                    message: String
                ) {
                    onProgress(stage, percent, downloadedBytes, totalBytes, message)
                }
            }

            module.callAttr(
                "download_audio",
                parsed.canonicalUrl,
                downloadsDir.absolutePath,
                cacheDir.absolutePath,
                quickJsPath,
                formatPref,
                updateDir.absolutePath,
                callback
            ).toString()
        } catch (err: Throwable) {
            if (err is YtDownloadDetailedException) throw err
            val summary = err.message ?: "Error al ejecutar yt-dlp en Chaquopy"
            throw YtDownloadDetailedException(
                summary = summary,
                rawDetail = "Stage: python_exec\nURL: ${parsed.canonicalUrl}\n${err.stackTraceToString()}"
            )
        }

        val resultJson = JSONObject(rawResult)
        if (!resultJson.optBoolean("ok", false)) {
            val err = resultJson.optString("error", "No se pudo descargar el audio")
            val rawErr = resultJson.optString("rawError", "").ifBlank { rawResult }
            throw YtDownloadDetailedException(
                summary = err,
                rawDetail = rawErr
            )
        }

        val audioPath = resultJson.getString("audioPath")
        val rawThumbPath = resultJson.optString("thumbnailPath", "")
        val title = resultJson.optString("title", "Pista descargada")
        val artist = resultJson.optString("artist", "Artista desconocido")
        val album = resultJson.optString("album", "Descargas Aura")
        val pyDurationMs = resultJson.optLong("durationMs", 0L)
        val pyAbr = resultJson.optInt("abr", 0)
        val pyAsr = resultJson.optInt("asr", 0)

        val audioFile = File(audioPath)
        val trackId = sha256Short(Uri.fromFile(audioFile).toString())

        var persistedArtworkPath: String? = null
        if (rawThumbPath.isNotBlank() && File(rawThumbPath).exists()) {
            runCatching {
                val webp = AuraArtworkProcessor.convertToLosslessWebp(
                    context = appContext,
                    sourcePath = rawThumbPath,
                    trackId = trackId
                )
                persistedArtworkPath = AuraArtworkProcessor.commitCustomArtwork(
                    context = appContext,
                    pendingOrExistingPath = webp.webpPath,
                    trackId = trackId
                )
            }
        }

        onProgress("verifying", 98.0, audioFile.length(), audioFile.length(), "Verificando integridad y metadatos con Rust Lofty...")
        val rustCheck = AuraRustYtBridge.verifyAndTagAudio(
            audioPath = audioPath,
            title = title,
            artist = artist,
            album = album,
            artworkPath = rawThumbPath.takeIf { it.isNotBlank() && File(it).exists() }
                ?: persistedArtworkPath
        )

        if (!rustCheck.valid) {
            val fileSize = audioFile.length()
            audioFile.delete()
            if (rawThumbPath.isNotBlank()) File(rawThumbPath).delete()
            val summary = rustCheck.error ?: "El archivo descargado está corrupto"
            throw YtDownloadDetailedException(
                summary = summary,
                rawDetail = "Stage: rust_verify_lofty\nURL: ${parsed.canonicalUrl}\nAudioPath: $audioPath\nBytes: $fileSize\nError: $summary"
            )
        }

        if (rawThumbPath.isNotBlank()) {
            runCatching { File(rawThumbPath).delete() }
        }

        val finalDurationMs = if (rustCheck.durationMs > 0L) rustCheck.durationMs else pyDurationMs
        val finalBitrate = if (rustCheck.bitrateKbps > 0) rustCheck.bitrateKbps else pyAbr
        val finalSampleRate = if (rustCheck.sampleRateHz > 0) rustCheck.sampleRateHz else pyAsr

        onProgress("done", 100.0, audioFile.length(), audioFile.length(), "Listo para reproducir")

        AuraTrackMetadata(
            id = trackId,
            uri = Uri.fromFile(audioFile).toString(),
            title = title,
            artist = artist,
            album = album,
            folderName = "Descargas Aura",
            durationMs = finalDurationMs,
            mimeType = rustCheck.mimeType,
            bitrateKbps = finalBitrate,
            sampleRateHz = finalSampleRate,
            artworkPath = persistedArtworkPath
        )
    }

    private fun sha256Short(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return digest.take(12).joinToString("") { "%02x".format(it) }
    }
}
