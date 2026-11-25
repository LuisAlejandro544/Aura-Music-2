// =============================================================================
// AuraRustYtBridge.kt — Puente JNI hacia el crate Rust `aura_yt_engine`
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Carga la librería nativa `libaura_yt_rust.so` (compilada por cargo-ndk para
//   armeabi-v7a y arm64-v8a) y expone:
//   1. `parseMediaUrl`: validación y canonicalización de enlaces YouTube/media
//      en Rust antes de llamar al intérprete Python.
//   2. `verifyAndTagAudio`: verificación de bytes mágicos (anti-HTML/corrupto),
//      extracción precisa de sampleRate/bitrate/duración con `lofty` (incluso en
//      Android 9-11) e incrustación nativa de etiquetas + carátula sin FFmpeg.
//   3. `getQuickJsBinaryPath`: ruta ejecutable en `nativeLibraryDir` del
//      binario Rust QuickJS-ng (`libaura_qjs.so`) usado por `yt-dlp-ejs`.
// =============================================================================

package com.auramusic.player

import android.content.Context
import org.json.JSONObject
import java.io.File

data class RustUrlParseResult(
    val valid: Boolean,
    val canonicalUrl: String,
    val videoId: String?,
    val host: String,
    val isYouTube: Boolean,
    val error: String?
)

data class RustAudioVerifyResult(
    val valid: Boolean,
    val container: String,
    val mimeType: String,
    val durationMs: Long,
    val bitrateKbps: Int,
    val sampleRateHz: Int,
    val channels: Int,
    val tagsEmbedded: Boolean,
    val artworkEmbedded: Boolean,
    val fileSizeBytes: Long,
    val error: String?
)

object AuraRustYtBridge {

    init {
        System.loadLibrary("aura_yt_rust")
    }

    @JvmStatic
    private external fun nativeEngineInfo(): String

    @JvmStatic
    private external fun nativeParseMediaUrl(rawUrl: String): String

    @JvmStatic
    private external fun nativeVerifyAndTagAudio(
        audioPath: String,
        title: String,
        artist: String,
        album: String,
        artworkPath: String
    ): String

    fun getQuickJsBinaryPath(context: Context): String {
        val binFile = File(context.applicationInfo.nativeLibraryDir, "libaura_qjs.so")
        return binFile.absolutePath
    }

    fun getEngineInfoJson(context: Context): JSONObject {
        val obj = JSONObject(nativeEngineInfo())
        val qjsPath = getQuickJsBinaryPath(context)
        val qjsFile = File(qjsPath)
        obj.put("quickjsBinaryPath", qjsPath)
        obj.put("quickjsBinaryExists", qjsFile.exists() && qjsFile.canExecute())
        return obj
    }

    fun parseMediaUrl(rawUrl: String): RustUrlParseResult {
        val obj = JSONObject(nativeParseMediaUrl(rawUrl))
        return RustUrlParseResult(
            valid = obj.optBoolean("valid", false),
            canonicalUrl = obj.optString("canonicalUrl", ""),
            videoId = obj.optString("videoId").takeIf { it.isNotBlank() && it != "null" },
            host = obj.optString("host", ""),
            isYouTube = obj.optBoolean("isYouTube", false),
            error = obj.optString("error").takeIf { it.isNotBlank() && it != "null" }
        )
    }

    fun verifyAndTagAudio(
        audioPath: String,
        title: String,
        artist: String,
        album: String,
        artworkPath: String?
    ): RustAudioVerifyResult {
        val obj = JSONObject(
            nativeVerifyAndTagAudio(
                audioPath = audioPath,
                title = title,
                artist = artist,
                album = album,
                artworkPath = artworkPath ?: ""
            )
        )
        return RustAudioVerifyResult(
            valid = obj.optBoolean("valid", false),
            container = obj.optString("container", ""),
            mimeType = obj.optString("mimeType", "audio/mp4"),
            durationMs = obj.optLong("durationMs", 0L),
            bitrateKbps = obj.optInt("bitrateKbps", 0),
            sampleRateHz = obj.optInt("sampleRateHz", 0),
            channels = obj.optInt("channels", 0),
            tagsEmbedded = obj.optBoolean("tagsEmbedded", false),
            artworkEmbedded = obj.optBoolean("artworkEmbedded", false),
            fileSizeBytes = obj.optLong("fileSizeBytes", 0L),
            error = obj.optString("error").takeIf { it.isNotBlank() && it != "null" }
        )
    }
}
