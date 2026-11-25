// =============================================================================
// AuraArtworkProcessor.kt — Conversión nativa de carátulas a WebP sin pérdida
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Procesa imágenes elegidas por el usuario desde la galería en un hilo de E/S
//   (Dispatchers.IO) usando Kotlin Coroutines y ImageDecoder nativo (API 28+):
//   - Decodifica la imagen seleccionada por el sistema sin bloquear la interfaz.
//   - La codifica en formato WebP con compresión máxima sin pérdida de calidad:
//     * Android 11+ (API 30+): Bitmap.CompressFormat.WEBP_LOSSLESS con calidad 100
//       (esfuerzo máximo de compresión sin pérdida).
//     * Android 9-10 (API 28-29): Bitmap.CompressFormat.WEBP a calidad 100 para
//       conservar compatibilidad completa con minSdk = 28 (32 y 64 bits).
//   - Mantiene un flujo seguro de vista previa (cacheDir/pending_artworks) y
//     guardado persistente (filesDir/custom_artworks) limpiando archivos previos.
// =============================================================================

package com.auramusic.player

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import kotlin.math.max

data class LosslessWebpConversionResult(
    val webpPath: String,
    val byteSize: Long,
    val width: Int,
    val height: Int,
    val isLossless: Boolean
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "webpPath" to webpPath,
        "byteSize" to byteSize,
        "width" to width,
        "height" to height,
        "isLossless" to isLossless
    )
}

object AuraArtworkProcessor {

    private const val PENDING_DIR = "pending_artworks"
    private const val CUSTOM_DIR = "custom_artworks"
    // Límite seguro para evitar OutOfMemoryError en dispositivos de 32 bits
    // únicamente con fotos descomunales (> 4096 px por lado).
    private const val MAX_SAFE_DIMENSION_PX = 4096

    /**
     * Convierte una imagen temporal seleccionada de galería a WebP sin pérdida
     * en cacheDir/pending_artworks para vista previa inmediata antes de guardar.
     */
    suspend fun convertToLosslessWebp(
        context: Context,
        sourcePath: String,
        trackId: String
    ): LosslessWebpConversionResult = withContext(Dispatchers.IO) {
        val sourceFile = File(sourcePath)
        require(sourceFile.exists() && sourceFile.length() > 0L) {
            "No se encontró la imagen seleccionada"
        }

        val source = ImageDecoder.createSource(sourceFile)
        val bitmap = ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
            decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            decoder.isMutableRequired = false

            val maxSide = max(info.size.width, info.size.height)
            if (maxSide > MAX_SAFE_DIMENSION_PX) {
                var sampleSize = 1
                while (maxSide / sampleSize > MAX_SAFE_DIMENSION_PX) {
                    sampleSize *= 2
                }
                decoder.setTargetSampleSize(sampleSize)
            }
        }

        val pendingDir = File(context.cacheDir, PENDING_DIR).apply {
            if (!exists()) mkdirs()
        }
        // Limpia vistas previas pendientes anteriores del mismo track
        pendingDir.listFiles { file ->
            file.name.startsWith("${trackId}_")
        }?.forEach { it.delete() }

        val outFile = File(pendingDir, "${trackId}_${System.currentTimeMillis()}.webp")
        val width = bitmap.width
        val height = bitmap.height
        val usesTrueLossless = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R

        try {
            FileOutputStream(outFile).use { fos ->
                val compressed = if (usesTrueLossless) {
                    bitmap.compress(Bitmap.CompressFormat.WEBP_LOSSLESS, 100, fos)
                } else {
                    @Suppress("DEPRECATION")
                    bitmap.compress(Bitmap.CompressFormat.WEBP, 100, fos)
                }
                check(compressed) { "No se pudo comprimir la imagen a formato WebP" }
                fos.flush()
            }
        } finally {
            bitmap.recycle()
        }

        LosslessWebpConversionResult(
            webpPath = outFile.absolutePath,
            byteSize = outFile.length(),
            width = width,
            height = height,
            isLossless = usesTrueLossless
        )
    }

    /**
     * Mueve la carátula WebP aprobada desde caché temporal a almacenamiento
     * persistente (filesDir/custom_artworks) y elimina versiones previas de la pista.
     */
    suspend fun commitCustomArtwork(
        context: Context,
        pendingOrExistingPath: String,
        trackId: String
    ): String = withContext(Dispatchers.IO) {
        val srcFile = File(pendingOrExistingPath)
        require(srcFile.exists()) { "La carátula WebP preparada no existe" }

        val customDir = File(context.filesDir, CUSTOM_DIR).apply {
            if (!exists()) mkdirs()
        }

        // Si ya está dentro de custom_artworks, conservarla sin duplicar
        if (srcFile.parentFile?.absolutePath == customDir.absolutePath) {
            return@withContext srcFile.absolutePath
        }

        // Eliminar carátulas personalizadas anteriores de este track
        customDir.listFiles { file ->
            file.name.startsWith("${trackId}_")
        }?.forEach { it.delete() }

        val destFile = File(customDir, "${trackId}_${System.currentTimeMillis()}.webp")
        srcFile.copyTo(destFile, overwrite = true)
        srcFile.delete()

        destFile.absolutePath
    }

    /**
     * Elimina cualquier carátula personalizada persistente asociada a una pista
     * (al restaurar la carátula original o eliminar la canción de la biblioteca).
     */
    suspend fun deleteCustomArtworksForTrack(
        context: Context,
        trackId: String
    ) = withContext(Dispatchers.IO) {
        val customDir = File(context.filesDir, CUSTOM_DIR)
        if (customDir.exists()) {
            customDir.listFiles { file ->
                file.name.startsWith("${trackId}_")
            }?.forEach { it.delete() }
        }
        val pendingDir = File(context.cacheDir, PENDING_DIR)
        if (pendingDir.exists()) {
            pendingDir.listFiles { file ->
                file.name.startsWith("${trackId}_")
            }?.forEach { it.delete() }
        }
    }
}
