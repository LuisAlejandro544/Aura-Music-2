// =============================================================================
// AuraTrackMetadata.kt — Extractor asíncrono de metadatos y carátulas locales
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Lee etiquetas ID3/Vorbis/MP4 (título, artista, álbum, duración, bitrate,
//   sampleRate, tipo MIME) y extrae la carátula incrustada de cada archivo de
//   audio importado por el usuario usando MediaMetadataRetriever.
//
// Por qué usa Coroutines (Dispatchers.IO):
//   Decodificar encabezados y carátulas de disco es una operación de E/S pesada.
//   Ejecutarlo en Dispatchers.IO mantiene el hilo principal (UI) completamente
//   libre a 60/120 fps incluso si el usuario importa cientos de canciones.
// =============================================================================

package com.auramusic.player

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

data class AuraTrackMetadata(
    val id: String,
    val uri: String,
    val title: String,
    val artist: String,
    val album: String,
    val folderName: String,
    val durationMs: Long,
    val mimeType: String,
    val bitrateKbps: Int,
    val sampleRateHz: Int,
    val artworkPath: String?
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "uri" to uri,
        "title" to title,
        "artist" to artist,
        "album" to album,
        "folderName" to folderName,
        "durationMs" to durationMs,
        "mimeType" to mimeType,
        "bitrateKbps" to bitrateKbps,
        "sampleRateHz" to sampleRateHz,
        "artworkPath" to artworkPath
    )
}

object AuraMetadataExtractor {

    /**
     * Extrae metadatos técnicos y carátula en segundo plano (Dispatchers.IO).
     * Guarda la carátula comprimida en cacheDir/artworks/ para evitar cargar
     * bitmaps crudos repetidamente desde los archivos de audio.
     */
    suspend fun extract(
        context: Context,
        uri: Uri,
        folderName: String = "Música Importada",
        fallbackDisplayName: String? = null
    ): AuraTrackMetadata? = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val uriString = uri.toString()
        val trackId = sha256Short(uriString)
        val displayName = fallbackDisplayName ?: queryDisplayName(context, uri) ?: "Pista local"
        val cleanName = displayName.substringBeforeLast('.')

        val retriever = MediaMetadataRetriever()
        var title = cleanName
        var artist = "Artista desconocido"
        var album = folderName
        var durationMs = 0L
        var mimeType = resolver.getType(uri) ?: inferMimeFromName(displayName)
        var bitrateKbps = 0
        var sampleRateHz = 0
        var artworkPath: String? = null

        try {
            retriever.setDataSource(context, uri)

            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
                ?.trim()?.takeIf { it.isNotEmpty() }?.let { title = it }

            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
                ?.trim()?.takeIf { it.isNotEmpty() }?.let { artist = it }

            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
                ?.trim()?.takeIf { it.isNotEmpty() }?.let { album = it }

            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull()?.let { durationMs = it }

            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_MIMETYPE)
                ?.takeIf { it.isNotBlank() }?.let { mimeType = it }

            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_BITRATE)
                ?.toIntOrNull()?.let { bitrateKbps = it / 1000 }

            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_SAMPLERATE)
                    ?.toIntOrNull()?.let { sampleRateHz = it }
            }

            // Cachear carátula incrustada de forma atómica solo si aún no existe en disco
            val embeddedBytes = retriever.embeddedPicture
            if (embeddedBytes != null && embeddedBytes.isNotEmpty()) {
                val artDir = File(context.cacheDir, "artworks").apply {
                    if (!exists()) mkdirs()
                }
                val artFile = File(artDir, "$trackId.jpg")
                if (!artFile.exists() || artFile.length() == 0L) {
                    val tempFile = File(artDir, "$trackId.tmp.${Thread.currentThread().id}")
                    try {
                        FileOutputStream(tempFile).use { fos ->
                            fos.write(embeddedBytes)
                        }
                        if (!artFile.exists() || artFile.length() == 0L) {
                            if (!tempFile.renameTo(artFile)) {
                                tempFile.copyTo(artFile, overwrite = true)
                            }
                        }
                    } finally {
                        if (tempFile.exists()) {
                            tempFile.delete()
                        }
                    }
                }
                if (artFile.exists() && artFile.length() > 0L) {
                    artworkPath = artFile.absolutePath
                }
            }
        } catch (_: Exception) {
            // Si algún archivo tiene metadatos corruptos, conservamos el nombre
            // legible y dejamos que ExoPlayer intente reproducir el stream.
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {
            }
        }

        AuraTrackMetadata(
            id = trackId,
            uri = uriString,
            title = title,
            artist = artist,
            album = album,
            folderName = folderName,
            durationMs = durationMs,
            mimeType = mimeType,
            bitrateKbps = bitrateKbps,
            sampleRateHz = sampleRateHz,
            artworkPath = artworkPath
        )
    }

    private fun queryDisplayName(context: Context, uri: Uri): String? {
        return try {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                        if (idx >= 0) cursor.getString(idx) else null
                    } else null
                }
        } catch (_: Exception) {
            null
        }
    }

    private fun inferMimeFromName(name: String): String {
        return when (name.substringAfterLast('.', "").lowercase()) {
            "flac" -> "audio/flac"
            "wav" -> "audio/wav"
            "m4a", "aac" -> "audio/mp4"
            "ogg", "opus" -> "audio/ogg"
            else -> "audio/mpeg"
        }
    }

    private fun sha256Short(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return digest.take(12).joinToString("") { "%02x".format(it) }
    }
}
