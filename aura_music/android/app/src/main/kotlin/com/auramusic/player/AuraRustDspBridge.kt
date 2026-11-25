// =============================================================================
// AuraRustDspBridge.kt — Puente JNI hacia el motor DSP nativo `aura_dsp`
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Carga `libaura_dsp.so` (compilada por cargo-ndk para armeabi-v7a y
//   arm64-v8a), persiste la configuración del ecualizador y del procesador
//   Audio 8D en SharedPreferences para restaurarla automáticamente aunque el
//   servicio arranque en segundo plano, detecta la ruta de salida (auriculares
//   vs altavoz) mediante AudioManager y sincroniza de forma lock-free todos
//   los parámetros con Rust para procesar buffers PCM en tiempo real.
// =============================================================================

package com.auramusic.player

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
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
        "engine" to (engineInfo["engine"] ?: "Biquad IIR 5-band + 8D Orbital + Soft Limiter"),
        "arch" to (engineInfo["arch"] ?: "")
    )
}

data class AuraSpatial8dConfig(
    val enabled: Boolean = false,
    val mode: String = "auto",
    val resolvedOutput: String = "speaker",
    val speedHz: Float = 0.16f,
    val intensity: Float = 0.75f
) {
    fun toMap(engineInfo: Map<String, Any?> = emptyMap()): Map<String, Any?> = mapOf(
        "enabled" to enabled,
        "mode" to mode,
        "resolvedOutput" to resolvedOutput,
        "speedHz" to speedHz.toDouble(),
        "intensity" to intensity.toDouble(),
        "rustCrate" to (engineInfo["rustCrate"] ?: "aura_dsp"),
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

    private const val KEY_8D_ENABLED = "spatial8d_enabled"
    private const val KEY_8D_MODE = "spatial8d_mode"
    private const val KEY_8D_SPEED_HZ = "spatial8d_speed_hz"
    private const val KEY_8D_INTENSITY = "spatial8d_intensity"

    private const val BAND_COUNT = 5

    @Volatile
    private var loadedFromPrefs = false

    @Volatile
    private var currentConfig = AuraEqualizerConfig()

    @Volatile
    private var currentSpatial8dConfig = AuraSpatial8dConfig()

    @Volatile
    var onSpatial8dRouteChanged: ((Map<String, Any?>) -> Unit)? = null

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
    private external fun nativeSetSpatial8dParameters(
        enabled: Boolean,
        outputMode: Int,
        speedHz: Float,
        intensity: Float
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

    fun detectAudioOutputType(context: Context): String {
        val manager = context.applicationContext
            .getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            ?: return "speaker"
        val outputs = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val hasHeadphones = outputs.any { dev ->
            when (dev.type) {
                AudioDeviceInfo.TYPE_WIRED_HEADSET,
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES,
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP,
                AudioDeviceInfo.TYPE_BLUETOOTH_SCO,
                AudioDeviceInfo.TYPE_USB_HEADSET,
                AudioDeviceInfo.TYPE_HEARING_AID -> true
                else -> Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    dev.type == AudioDeviceInfo.TYPE_BLE_HEADSET
            }
        }
        return if (hasHeadphones) "headphones" else "speaker"
    }

    private fun normalizeMode(mode: String?): String = when (mode) {
        "headphones", "speaker", "auto" -> mode
        else -> "auto"
    }

    private fun resolveOutputString(context: Context, mode: String): String {
        return when (mode) {
            "headphones" -> "headphones"
            "speaker" -> "speaker"
            else -> detectAudioOutputType(context)
        }
    }

    private fun outputStringToNativeInt(resolvedOutput: String): Int {
        return if (resolvedOutput == "headphones") 0 else 1
    }

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

            val s8dEnabled = prefs.getBoolean(KEY_8D_ENABLED, false)
            val s8dMode = normalizeMode(prefs.getString(KEY_8D_MODE, "auto"))
            val s8dSpeed = prefs.getFloat(KEY_8D_SPEED_HZ, 0.16f).coerceIn(0.05f, 0.50f)
            val s8dIntensity = prefs.getFloat(KEY_8D_INTENSITY, 0.75f).coerceIn(0f, 1f)
            val resolved = resolveOutputString(context, s8dMode)
            val s8dCfg = AuraSpatial8dConfig(
                enabled = s8dEnabled,
                mode = s8dMode,
                resolvedOutput = resolved,
                speedHz = s8dSpeed,
                intensity = s8dIntensity
            )
            currentSpatial8dConfig = s8dCfg
            nativeSetSpatial8dParameters(
                s8dCfg.enabled,
                outputStringToNativeInt(resolved),
                s8dCfg.speedHz,
                s8dCfg.intensity
            )

            loadedFromPrefs = true
            return cfg
        }
    }

    fun syncOutputRoute(context: Context) {
        loadSavedSettings(context)
        val prev = currentSpatial8dConfig
        val nextResolved = resolveOutputString(context, prev.mode)
        if (nextResolved == prev.resolvedOutput) return

        val updated = prev.copy(resolvedOutput = nextResolved)
        currentSpatial8dConfig = updated
        nativeSetSpatial8dParameters(
            updated.enabled,
            outputStringToNativeInt(nextResolved),
            updated.speedHz,
            updated.intensity
        )
        onSpatial8dRouteChanged?.invoke(updated.toMap(getEngineInfoMap()))
    }

    fun updateSettings(
        context: Context,
        enabled: Boolean,
        presetId: String,
        preampDb: Float,
        limiterEnabled: Boolean,
        bandGainsDb: List<Double>
    ): Map<String, Any?> {
        loadSavedSettings(context)
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

    fun updateSpatial8dSettings(
        context: Context,
        enabled: Boolean,
        mode: String,
        speedHz: Float,
        intensity: Float
    ): Map<String, Any?> {
        loadSavedSettings(context)
        val normMode = normalizeMode(mode)
        val clampedSpeed = speedHz.coerceIn(0.05f, 0.50f)
        val clampedIntensity = intensity.coerceIn(0f, 1f)
        val resolved = resolveOutputString(context, normMode)
        val cfg = AuraSpatial8dConfig(
            enabled = enabled,
            mode = normMode,
            resolvedOutput = resolved,
            speedHz = clampedSpeed,
            intensity = clampedIntensity
        )
        currentSpatial8dConfig = cfg
        loadedFromPrefs = true

        nativeSetSpatial8dParameters(
            cfg.enabled,
            outputStringToNativeInt(resolved),
            cfg.speedHz,
            cfg.intensity
        )

        val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean(KEY_8D_ENABLED, cfg.enabled)
            .putString(KEY_8D_MODE, cfg.mode)
            .putFloat(KEY_8D_SPEED_HZ, cfg.speedHz)
            .putFloat(KEY_8D_INTENSITY, cfg.intensity)
            .apply()

        return cfg.toMap(getEngineInfoMap())
    }

    fun getStateMap(context: Context): Map<String, Any?> {
        val cfg = loadSavedSettings(context)
        return cfg.toMap(getEngineInfoMap())
    }

    fun getSpatial8dStateMap(context: Context): Map<String, Any?> {
        loadSavedSettings(context)
        val prev = currentSpatial8dConfig
        val freshResolved = resolveOutputString(context, prev.mode)
        val effective = if (freshResolved != prev.resolvedOutput) {
            val updated = prev.copy(resolvedOutput = freshResolved)
            currentSpatial8dConfig = updated
            nativeSetSpatial8dParameters(
                updated.enabled,
                outputStringToNativeInt(freshResolved),
                updated.speedHz,
                updated.intensity
            )
            updated
        } else {
            prev
        }
        return effective.toMap(getEngineInfoMap())
    }

    fun getEngineInfoMap(): Map<String, Any?> {
        return runCatching {
            val obj = JSONObject(nativeEngineInfo())
            mapOf(
                "rustCrate" to obj.optString("rustCrate", "aura_dsp"),
                "engine" to obj.optString("engine", "Biquad IIR 5-band + 8D Orbital + Soft Limiter"),
                "arch" to obj.optString("arch", "")
            )
        }.getOrDefault(
            mapOf(
                "rustCrate" to "aura_dsp",
                "engine" to "Biquad IIR 5-band + 8D Orbital + Soft Limiter",
                "arch" to ""
            )
        )
    }

    fun isDspEnabled(): Boolean = currentConfig.enabled || currentSpatial8dConfig.enabled

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
        if (!isDspEnabled() || byteCount <= 0) return
        nativeProcessPcmBuffer(
            buffer = directBuffer,
            byteCount = byteCount,
            sampleRate = sampleRate,
            channelCount = channelCount,
            isFloat = isFloat
        )
    }
}
