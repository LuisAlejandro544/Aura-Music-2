// =============================================================================
// AuraRustDspProcessor.kt — AudioProcessor de Media3 conectado a Rust `aura_dsp`
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Se inserta en la cadena de renderizado de ExoPlayer (DefaultAudioSink)
//   para procesar las muestras PCM decodificadas (16-bit o Float 32-bit)
//   directamente sobre un DirectByteBuffer en Rust antes de enviarlas al DAC.
//   Cuando el ecualizador está desactivado, pasa los bytes intactos sin alterar
//   la señal original.
// =============================================================================

package com.auramusic.player

import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.util.UnstableApi
import java.nio.ByteBuffer

@OptIn(UnstableApi::class)
class AuraRustDspProcessor : BaseAudioProcessor() {

    private var isFloatEncoding = false

    override fun onConfigure(
        inputAudioFormat: AudioProcessor.AudioFormat
    ): AudioProcessor.AudioFormat {
        return when (inputAudioFormat.encoding) {
            C.ENCODING_PCM_16BIT -> {
                isFloatEncoding = false
                inputAudioFormat
            }
            C.ENCODING_PCM_FLOAT -> {
                isFloatEncoding = true
                inputAudioFormat
            }
            else -> AudioProcessor.AudioFormat.NOT_SUPPORTED
        }
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val remaining = inputBuffer.remaining()
        if (remaining <= 0) return

        val outBuffer = replaceOutputBuffer(remaining)
        outBuffer.put(inputBuffer)
        outBuffer.flip()

        if (AuraRustDspBridge.isDspEnabled() &&
            inputAudioFormat.sampleRate > 0 &&
            inputAudioFormat.channelCount > 0
        ) {
            AuraRustDspBridge.processPcmBuffer(
                directBuffer = outBuffer,
                byteCount = remaining,
                sampleRate = inputAudioFormat.sampleRate,
                channelCount = inputAudioFormat.channelCount,
                isFloat = isFloatEncoding
            )
        }
    }

    override fun onFlush() {
        AuraRustDspBridge.resetFilterState()
    }

    override fun onReset() {
        isFloatEncoding = false
        AuraRustDspBridge.resetFilterState()
    }
}
