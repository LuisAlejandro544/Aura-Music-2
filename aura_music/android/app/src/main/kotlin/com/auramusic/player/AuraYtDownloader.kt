// =============================================================================
// AuraYtDownloader.kt — Orquestador Kotlin de descarga con yt-dlp + Rust
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Ejecuta todo el pipeline de descarga y auto-actualización desde URL en
//   Dispatchers.IO sin bloquear jamás la UI:
//   1. Valida y limpia la URL en Rust (`AuraRustYtBridge.parseMediaUrl`).
//   2. Si el auto-actualizador está activo y pasaron >= 24h desde el último
//      chequeo, consulta PyPI y actualiza `yt-dlp` y `yt-dlp-ejs` en
//      `filesDir/yt_dlp_updates/` (con verificación SHA-256) antes de bajar.
//   3. Inicia el entorno Python minimalista de Chaquopy (`yt-dlp --no-deps`,
//      `yt-dlp-ejs --no-deps`, `certifi`) de forma diferida al primer uso.
//   4. Ejecuta `aura_yt_engine.download_audio` pasando la ruta ejecutable de
//      `libaura_qjs.so` (Rust QuickJS-ng) para resolver desafíos JS de YouTube.
//   5. Convierte la carátula descargada a WebP sin pérdida persistente mediante
//      `AuraArtworkProcessor` en `filesDir/custom_artworks/`.
//   6. Verifica integridad del audio, lee bitrate/sampleRate/duración e
//      incrusta metadatos + portada en Rust (`AuraRustYtBridge.verifyAndTagAudio`
//      con `lofty`), devolviendo un `AuraTrackMetadata` listo para ExoPlayer.
// =============================================================================

package com.auramusic.player

import android.content.Context
import android.net.Uri
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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

interface YtUpdateProgressCallback {
    fun onProgress(
        stage: String,
        packageName: String,
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

    private const val PREFS_NAME = "aura_yt_prefs"
    private const val KEY_AUTO_UPDATE = "auto_update_enabled"
    private const val KEY_LAST_CHECK_MS = "last_update_check_ms"
    private const val KEY_CACHED_PY_VER = "cached_python_version"
    private const val KEY_CACHED_YTDLP_VER = "cached_yt_dlp_version"
    private const val KEY_CACHED_EJS_VER = "cached_ejs_version"

    private const val AUTO_UPDATE_INTERVAL_MS = 24L * 60L * 60L * 1000L

    private val pythonInitLock = Any()
    private val engineOpMutex = Mutex()

    private fun ensurePythonStarted(context: Context): Python {
        val appContext = context.applicationContext
        synchronized(pythonInitLock) {
            if (!Python.isStarted()) {
                Python.start(AndroidPlatform(appContext))
            }
            return Python.getInstance()
        }
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isAutoUpdateEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_AUTO_UPDATE, true)

    suspend fun setAutoUpdateEnabled(context: Context, enabled: Boolean): Boolean =
        withContext(Dispatchers.IO) {
            prefs(context).edit().putBoolean(KEY_AUTO_UPDATE, enabled).apply()
            enabled
        }

    private fun cacheVersions(
        context: Context,
        pythonVer: String?,
        ytDlpVer: String?,
        ejsVer: String?
    ) {
        val editor = prefs(context).edit()
        if (!pythonVer.isNullOrBlank()) editor.putString(KEY_CACHED_PY_VER, pythonVer)
        if (!ytDlpVer.isNullOrBlank() && ytDlpVer != "unknown") {
            editor.putString(KEY_CACHED_YTDLP_VER, ytDlpVer)
        }
        if (!ejsVer.isNullOrBlank() && ejsVer != "unknown") {
            editor.putString(KEY_CACHED_EJS_VER, ejsVer)
        }
        editor.apply()
    }

    suspend fun getEngineStatus(
        context: Context,
        includePython: Boolean = false
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val appContext = context.applicationContext
        val rustInfo = AuraRustYtBridge.getEngineInfoJson(appContext)
        val updateDirFile = File(appContext.filesDir, YT_UPDATES_DIR)
        val usingUpdatedYtDlp = File(updateDirFile, "yt_dlp").isDirectory
        val usingUpdatedEjs = File(updateDirFile, "yt_dlp_ejs").isDirectory
        val p = prefs(appContext)
        val autoUpdate = p.getBoolean(KEY_AUTO_UPDATE, true)
        val lastCheckMs = p.getLong(KEY_LAST_CHECK_MS, 0L)

        val pythonStarted = Python.isStarted()
        if (!pythonStarted && !includePython) {
            return@withContext mapOf(
                "pythonStarted" to false,
                "pythonVersion" to (p.getString(KEY_CACHED_PY_VER, "") ?: ""),
                "ytDlpVersion" to (p.getString(KEY_CACHED_YTDLP_VER, "") ?: ""),
                "ejsVersion" to (p.getString(KEY_CACHED_EJS_VER, "") ?: ""),
                "quickjsBinaryPath" to rustInfo.optString("quickjsBinaryPath", ""),
                "quickjsReady" to rustInfo.optBoolean("quickjsBinaryExists", false),
                "rustCrate" to rustInfo.optString("rustCrate", ""),
                "audioProcessor" to rustInfo.optString("audioProcessor", ""),
                "arch" to rustInfo.optString("arch", ""),
                "usingUpdatedYtDlp" to usingUpdatedYtDlp,
                "usingUpdatedEjs" to usingUpdatedEjs,
                "autoUpdateEnabled" to autoUpdate,
                "lastUpdateCheckMs" to lastCheckMs
            )
        }

        val py = ensurePythonStarted(appContext)
        val module = py.getModule("aura_yt_engine")
        val qjsPath = AuraRustYtBridge.getQuickJsBinaryPath(appContext)
        val updateDir = updateDirFile.absolutePath
        val pyJson = JSONObject(module.callAttr("get_engine_info", qjsPath, updateDir).toString())

        val pyVer = pyJson.optString("pythonVersion", "")
        val ytVer = pyJson.optString("ytDlpVersion", "")
        val ejsVer = pyJson.optString("ejsVersion", "")
        cacheVersions(appContext, pyVer, ytVer, ejsVer)

        mapOf(
            "pythonStarted" to true,
            "pythonVersion" to pyVer,
            "ytDlpVersion" to ytVer,
            "ejsVersion" to ejsVer,
            "quickjsBinaryPath" to rustInfo.optString("quickjsBinaryPath", ""),
            "quickjsReady" to rustInfo.optBoolean("quickjsBinaryExists", false),
            "rustCrate" to rustInfo.optString("rustCrate", ""),
            "audioProcessor" to rustInfo.optString("audioProcessor", ""),
            "arch" to rustInfo.optString("arch", ""),
            "usingUpdatedYtDlp" to pyJson.optBoolean("usingUpdatedYtDlp", usingUpdatedYtDlp),
            "usingUpdatedEjs" to pyJson.optBoolean("usingUpdatedEjs", usingUpdatedEjs),
            "autoUpdateEnabled" to autoUpdate,
            "lastUpdateCheckMs" to lastCheckMs
        )
    }

    suspend fun checkUpdates(context: Context): Map<String, Any?> = withContext(Dispatchers.IO) {
        engineOpMutex.withLock {
            val appContext = context.applicationContext
            val updateDir = File(appContext.filesDir, YT_UPDATES_DIR).apply { if (!exists()) mkdirs() }
            val qjsPath = AuraRustYtBridge.getQuickJsBinaryPath(appContext)
            val py = ensurePythonStarted(appContext)
            val module = py.getModule("aura_yt_engine")
            val raw = module.callAttr("check_updates", updateDir.absolutePath, qjsPath).toString()
            val obj = JSONObject(raw)

            val checkedAtMs = obj.optLong("checkedAtMs", System.currentTimeMillis())
            if (obj.optBoolean("ok", false)) {
                prefs(appContext).edit().putLong(KEY_LAST_CHECK_MS, checkedAtMs).apply()
            }

            val ytObj = obj.optJSONObject("ytDlp") ?: JSONObject()
            val ejsObj = obj.optJSONObject("ytDlpEjs") ?: JSONObject()
            cacheVersions(
                appContext,
                null,
                ytObj.optString("installed", ""),
                ejsObj.optString("installed", "")
            )

            mapOf(
                "ok" to obj.optBoolean("ok", false),
                "checkedAtMs" to checkedAtMs,
                "hasUpdates" to obj.optBoolean("hasUpdates", false),
                "error" to obj.optString("error", ""),
                "ytDlp" to mapOf(
                    "installed" to ytObj.optString("installed", "unknown"),
                    "latest" to ytObj.optString("latest", ""),
                    "updateAvailable" to ytObj.optBoolean("updateAvailable", false)
                ),
                "ytDlpEjs" to mapOf(
                    "installed" to ejsObj.optString("installed", "unknown"),
                    "latest" to ejsObj.optString("latest", ""),
                    "updateAvailable" to ejsObj.optBoolean("updateAvailable", false)
                )
            )
        }
    }

    suspend fun updatePackages(
        context: Context,
        force: Boolean = false,
        onProgress: (stage: String, packageName: String, percent: Double, downloadedBytes: Long, totalBytes: Long, message: String) -> Unit = { _, _, _, _, _, _ -> }
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        engineOpMutex.withLock {
            runUpdateInternal(
                context = context.applicationContext,
                force = force,
                onProgress = onProgress
            )
        }
    }

    private fun runUpdateInternal(
        context: Context,
        force: Boolean,
        onProgress: (stage: String, packageName: String, percent: Double, downloadedBytes: Long, totalBytes: Long, message: String) -> Unit
    ): Map<String, Any?> {
        val updateDir = File(context.filesDir, YT_UPDATES_DIR).apply { if (!exists()) mkdirs() }
        val cacheDir = File(context.cacheDir, YT_CACHE_DIR).apply { if (!exists()) mkdirs() }
        val qjsPath = AuraRustYtBridge.getQuickJsBinaryPath(context)
        val py = ensurePythonStarted(context)
        val module = py.getModule("aura_yt_engine")

        val callback = object : YtUpdateProgressCallback {
            override fun onProgress(
                stage: String,
                packageName: String,
                percent: Double,
                downloadedBytes: Long,
                totalBytes: Long,
                message: String
            ) {
                onProgress(stage, packageName, percent, downloadedBytes, totalBytes, message)
            }
        }

        val raw = module.callAttr(
            "check_and_update_packages",
            updateDir.absolutePath,
            cacheDir.absolutePath,
            qjsPath,
            force,
            callback
        ).toString()

        val obj = JSONObject(raw)
        val checkedAtMs = obj.optLong("checkedAtMs", System.currentTimeMillis())
        if (obj.optBoolean("ok", false)) {
            prefs(context).edit().putLong(KEY_LAST_CHECK_MS, checkedAtMs).apply()
        }

        val ytObj = obj.optJSONObject("ytDlp") ?: JSONObject()
        val ejsObj = obj.optJSONObject("ytDlpEjs") ?: JSONObject()
        cacheVersions(
            context,
            null,
            ytObj.optString("installed", ""),
            ejsObj.optString("installed", "")
        )

        return mapOf(
            "ok" to obj.optBoolean("ok", false),
            "updatedAny" to obj.optBoolean("updatedAny", false),
            "checkedAtMs" to checkedAtMs,
            "message" to obj.optString("message", ""),
            "error" to obj.optString("error", ""),
            "ytDlp" to mapOf(
                "installed" to ytObj.optString("installed", "unknown"),
                "previous" to ytObj.optString("previous", ""),
                "latest" to ytObj.optString("latest", ""),
                "updated" to ytObj.optBoolean("updated", false),
                "updateAvailable" to ytObj.optBoolean("updateAvailable", false)
            ),
            "ytDlpEjs" to mapOf(
                "installed" to ejsObj.optString("installed", "unknown"),
                "previous" to ejsObj.optString("previous", ""),
                "latest" to ejsObj.optString("latest", ""),
                "updated" to ejsObj.optBoolean("updated", false),
                "updateAvailable" to ejsObj.optBoolean("updateAvailable", false)
            )
        )
    }

    suspend fun restoreBundledEngine(context: Context): Map<String, Any?> =
        withContext(Dispatchers.IO) {
            engineOpMutex.withLock {
                val appContext = context.applicationContext
                val updateDir = File(appContext.filesDir, YT_UPDATES_DIR)
                if (Python.isStarted()) {
                    val py = ensurePythonStarted(appContext)
                    val module = py.getModule("aura_yt_engine")
                    val raw = module.callAttr("clear_updates", updateDir.absolutePath).toString()
                    val obj = JSONObject(raw)
                    val ytVer = obj.optString("ytDlpVersion", "")
                    val ejsVer = obj.optString("ejsVersion", "")
                    cacheVersions(appContext, null, ytVer, ejsVer)
                    return@withLock mapOf(
                        "ok" to obj.optBoolean("ok", true),
                        "removed" to obj.optBoolean("removed", false),
                        "ytDlpVersion" to ytVer,
                        "ejsVersion" to ejsVer
                    )
                }

                var removed = false
                if (updateDir.exists()) {
                    removed = updateDir.deleteRecursively()
                    updateDir.mkdirs()
                }
                prefs(appContext).edit()
                    .remove(KEY_CACHED_YTDLP_VER)
                    .remove(KEY_CACHED_EJS_VER)
                    .apply()
                mapOf(
                    "ok" to true,
                    "removed" to removed,
                    "ytDlpVersion" to "",
                    "ejsVersion" to ""
                )
            }
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

        val rawResult = engineOpMutex.withLock {
            // Auto-actualizador silencioso cada 24h si está habilitado; nunca bloquea si no hay PyPI
            if (isAutoUpdateEnabled(appContext)) {
                val lastCheck = prefs(appContext).getLong(KEY_LAST_CHECK_MS, 0L)
                if (System.currentTimeMillis() - lastCheck >= AUTO_UPDATE_INTERVAL_MS) {
                    onProgress("resolving", 1.0, 0L, 0L, "Comprobando actualizaciones de yt-dlp...")
                    runCatching {
                        runUpdateInternal(
                            context = appContext,
                            force = false,
                            onProgress = { _, _, _, _, _, msg ->
                                onProgress("resolving", 1.5, 0L, 0L, msg)
                            }
                        )
                    }
                }
            }

            onProgress("python_init", 2.0, 0L, 0L, "Iniciando intérprete Python minimalista...")
            try {
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
