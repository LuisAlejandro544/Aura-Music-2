// =============================================================================
// AuraRustDspBridge.kt — Puente JNI hacia el motor DSP nativo `aura_dsp`
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Carga `libaura_dsp.so` (compilada por cargo-ndk para armeabi-v7a y
//   arm64-v8a), persiste la configuración del ecualizador en SharedPreferences
//   para restaurarla automáticamente aunque el servicio arranque en segundo
//   plano y sincroniza de forma lock-free las 5 bandas, preamp y limitador con
//   Rust para procesar buffers PCM en tiempo real.
// =============================================================================

package com.auramusic.player

import android.content.Context
import org.json.JSONObject
import java.nio.ByteBuffer

data class AuraEqualizerConfig(
    val enabled: Boolean = false,
    val presetId: String = "flat",
    val preampDb: Float = 0f,
    val limiterEnabled: Boolean = true,
    val bandGainsDb: FloatArray = floatArrayOf(0f, 0f, 0f, 0f, 0f)
) {
    fun toMap(engineInfo: Map<String, Any?> = emptyMap()): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "presetId" to presetId,
        "preampDb" to preampDb.toDouble(),
        "limiterEnabled" to limiterEnabled,
        "bandGainsDb" to bandGainsDb.map { it.toDouble() },
        "rustCrate" to (engineInfo["rustCrate"] ?: "aura_dsp"),
        "engine" to (engineInfo["engine"] ?: "Biquad IIR 5-band + Soft Limiter"),
        "arch" to (engineInfo["arch"] ?: "")
    )
}

object AuraRustDspBridge {

    private const val PREFS_NAME = "aura_dsp_prefs"
    private const val KEY_ENABLED = "eq_enabled"
    private const val KEY_PRESET = "eq_preset"
    private const val KEY_PREAMP = "eq_preamp"
    private const val KEY_LIMITER = "eq_limiter"
    private const val KEY_BANDS = "eq_bands"
    private const val BAND_COUNT = 5

    @Volatile
    private var loadedFromPrefs = false

    @Volatile
    private var currentConfig = AuraEqualizerConfig()

    init {
        System.loadLibrary("aura_dsp")
    }

    @JvmStatic
    private external fun nativeEngineInfo(): String

    @JvmStatic
    private external fun nativeSetParameters(
        enabled: Boolean,
        preampDb: Float,
        limiterEnabled: Boolean,
        bandGainsDb: FloatArray
    )

    @JvmStatic
    private external fun nativeResetState()

    @JvmStatic
    private external fun nativeProcessPcmBuffer(
        buffer: ByteBuffer,
        byteCount: Int,
        sampleRate: Int,
        channelCount: Int,
        isFloat: Boolean
    )

    fun loadSavedSettings(context: Context): AuraEqualizerConfig {
        if (loadedFromPrefs) return currentConfig
        synchronized(this) {
            if (loadedFromPrefs) return currentConfig
            val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val enabled = prefs.getBoolean(KEY_ENABLED, false)
            val presetId = prefs.getString(KEY_PRESET, "flat") ?: "flat"
            val preamp = prefs.getFloat(KEY_PREAMP, 0f).coerceIn(-6f, 6f)
            val limiter = prefs.getBoolean(KEY_LIMITER, true)
            val rawBands = prefs.getString(KEY_BANDS, null)
            val bands = FloatArray(BAND_COUNT) { 0f }
            if (!rawBands.isNullOrBlank()) {
                val parts = rawBands.split(",")
                for (i in 0 until minOf(BAND_COUNT, parts.size)) {
                    bands[i] = parts[i].toFloatOrNull()?.coerceIn(-12f, 12f) ?: 0f
                }
            }
            val cfg = AuraEqualizerConfig(
                enabled = enabled,
                presetId = presetId,
                preampDb = preamp,
                limiterEnabled = limiter,
                bandGainsDb = bands
            )
            currentConfig = cfg
            nativeSetParameters(cfg.enabled, cfg.preampDb, cfg.limiterEnabled, cfg.bandGainsDb)
            loadedFromPrefs = true
            return cfg
        }
    }

    fun updateSettings(
        context: Context,
        enabled: Boolean,
        presetId: String,
        preampDb: Float,
        limiterEnabled: Boolean,
        bandGainsDb: List<Double>
    ): Map<String, Any?> {
        val normalizedBands = FloatArray(BAND_COUNT) { idx ->
            bandGainsDb.getOrNull(idx)?.toFloat()?.coerceIn(-12f, 12f) ?: 0f
        }
        val clampedPreamp = preampDb.coerceIn(-6f, 6f)
        val cfg = AuraEqualizerConfig(
            enabled = enabled,
            presetId = presetId,
            preampDb = clampedPreamp,
            limiterEnabled = limiterEnabled,
            bandGainsDb = normalizedBands
        )
        currentConfig = cfg
        loadedFromPrefs = true

        // Sincronización atómica inmediata hacia el hilo de audio en Rust
        nativeSetParameters(cfg.enabled, cfg.preampDb, cfg.limiterEnabled, cfg.bandGainsDb)

        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_ENABLED, cfg.enabled)
            .putString(KEY_PRESET, cfg.presetId)
            .putFloat(KEY_PREAMP, cfg.preampDb)
            .putBoolean(KEY_LIMITER, cfg.limiterEnabled)
            .putString(KEY_BANDS, cfg.bandGainsDb.joinToString(","))
            .apply()

        return cfg.toMap(getEngineInfoMap())
    }

    fun getStateMap(context: Context): Map<String, Any?> {
        val cfg = loadSavedSettings(context)
        return cfg.toMap(getEngineInfoMap())
    }

    fun getEngineInfoMap(): Map<String, Any?> {
        return runCatching {
            val obj = JSONObject(nativeEngineInfo())
            mapOf(
                "rustCrate" to obj.optString("rustCrate", "aura_dsp"),
                "engine" to obj.optString("engine", "Biquad IIR 5-band + Soft Limiter"),
                "arch" to obj.optString("arch", "")
            )
        }.getOrDefault(
            mapOf(
                "rustCrate" to "aura_dsp",
                "engine" to "Biquad IIR 5-band + Soft Limiter",
                "arch" to ""
            )
        )
    }

    fun isDspEnabled(): Boolean = currentConfig.enabled

    fun resetFilterState() {
        nativeResetState()
    }

    fun processPcmBuffer(
        directBuffer: ByteBuffer,
        byteCount: Int,
        sampleRate: Int,
        channelCount: Int,
        isFloat: Boolean
    ) {
        if (!currentConfig.enabled || byteCount <= 0) return
        nativeProcessPcmBuffer(
            buffer = directBuffer,
            byteCount = byteCount,
            sampleRate = sampleRate,
            channelCount = channelCount,
            isFloat = isFloat
        )
    }
}
