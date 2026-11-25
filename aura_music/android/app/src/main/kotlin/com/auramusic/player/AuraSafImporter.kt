// =============================================================================
// AuraSafImporter.kt — Importación explícita mediante Storage Access Framework
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Implementa la decisión clave de diseño de Aura Music: NO escanear todo el
//   teléfono en segundo plano. En su lugar, abre los selectores nativos del
//   sistema Android (archivos múltiples o carpeta elegida) y solicita permisos
//   persistentes (takePersistableUriPermission) sobre las rutas seleccionadas
//   por la usuaria.
//
// Concurrencia inteligente:
//   Recorre el árbol de DocumentFile y extrae los metadatos de cada canción en
//   lotes paralelos limitados sobre Dispatchers.IO, reportando progreso en vivo
//   a Flutter sin congelar la interfaz.
// =============================================================================

package com.auramusic.player

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext

class AuraSafImporter(
    private val activity: Activity,
    private val scope: CoroutineScope,
    private val onProgress: (processed: Int, total: Int) -> Unit
) {
    companion object {
        const val REQUEST_PICK_AUDIO_FILES = 4101
        const val REQUEST_PICK_AUDIO_FOLDER = 4102

        private val SUPPORTED_EXTENSIONS = setOf(
            "mp3", "flac", "m4a", "aac", "wav", "ogg", "opus", "alac", "wma"
        )
    }

    private var pendingCallback: ((Result<List<AuraTrackMetadata>>) -> Unit)? = null

    fun launchPickAudioFiles(callback: (Result<List<AuraTrackMetadata>>) -> Unit) {
        pendingCallback = callback
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_PICK_AUDIO_FILES)
    }

    fun launchPickAudioFolder(callback: (Result<List<AuraTrackMetadata>>) -> Unit) {
        pendingCallback = callback
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST_PICK_AUDIO_FOLDER)
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_PICK_AUDIO_FILES && requestCode != REQUEST_PICK_AUDIO_FOLDER) {
            return false
        }

        val callback = pendingCallback ?: return true
        pendingCallback = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            callback(Result.success(emptyList()))
            return true
        }

        when (requestCode) {
            REQUEST_PICK_AUDIO_FILES -> {
                val uris = mutableListOf<Uri>()
                data.clipData?.let { clip ->
                    for (i in 0 until clip.itemCount) {
                        clip.getItemAt(i).uri?.let { uris.add(it) }
                    }
                } ?: data.data?.let { uris.add(it) }

                scope.launch {
                    val result = runCatching { processSelectedFiles(uris) }
                    withContext(Dispatchers.Main) { callback(result) }
                }
            }

            REQUEST_PICK_AUDIO_FOLDER -> {
                val treeUri = data.data
                if (treeUri == null) {
                    callback(Result.success(emptyList()))
                    return true
                }
                scope.launch {
                    val result = runCatching { processSelectedFolder(treeUri) }
                    withContext(Dispatchers.Main) { callback(result) }
                }
            }
        }
        return true
    }

    private suspend fun processSelectedFiles(uris: List<Uri>): List<AuraTrackMetadata> =
        withContext(Dispatchers.IO) {
            val total = uris.size
            var processed = 0
            val gate = Semaphore(4)

            val jobs = uris.map { uri ->
                async {
                    gate.withPermit {
                        takePersistablePermissionSafe(uri)
                        val meta = AuraMetadataExtractor.extract(
                            context = activity.applicationContext,
                            uri = uri,
                            folderName = "Pistas Importadas"
                        )
                        processed += 1
                        withContext(Dispatchers.Main) { onProgress(processed, total) }
                        meta
                    }
                }
            }
            jobs.awaitAll().filterNotNull()
        }

    private suspend fun processSelectedFolder(treeUri: Uri): List<AuraTrackMetadata> =
        withContext(Dispatchers.IO) {
            takePersistablePermissionSafe(treeUri)

            val rootDoc = DocumentFile.fromTreeUri(activity.applicationContext, treeUri)
                ?: return@withContext emptyList()
            val rootFolderName = rootDoc.name ?: "Carpeta Local"

            val audioDocs = mutableListOf<Pair<DocumentFile, String>>()
            collectAudioDocuments(rootDoc, rootFolderName, audioDocs)

            val total = audioDocs.size
            var processed = 0
            val gate = Semaphore(4)

            val jobs = audioDocs.map { (doc, folderLabel) ->
                async {
                    gate.withPermit {
                        val meta = AuraMetadataExtractor.extract(
                            context = activity.applicationContext,
                            uri = doc.uri,
                            folderName = folderLabel,
                            fallbackDisplayName = doc.name
                        )
                        processed += 1
                        withContext(Dispatchers.Main) { onProgress(processed, total) }
                        meta
                    }
                }
            }
            jobs.awaitAll().filterNotNull()
        }

    private fun collectAudioDocuments(
        dir: DocumentFile,
        folderName: String,
        output: MutableList<Pair<DocumentFile, String>>
    ) {
        val children = try {
            dir.listFiles()
        } catch (_: Exception) {
            emptyArray()
        }
        for (child in children) {
            if (child.isDirectory) {
                collectAudioDocuments(child, child.name ?: folderName, output)
            } else if (child.isFile && isSupportedAudio(child)) {
                output.add(child to folderName)
            }
        }
    }

    private fun isSupportedAudio(doc: DocumentFile): Boolean {
        val mime = doc.type?.lowercase() ?: ""
        if (mime.startsWith("audio/")) return true
        val ext = doc.name?.substringAfterLast('.', "")?.lowercase() ?: ""
        return ext in SUPPORTED_EXTENSIONS
    }

    private fun takePersistablePermissionSafe(uri: Uri) {
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: SecurityException) {
            // Algunos proveedores temporales no permiten permisos persistentes;
            // aún así funciona durante la sesión activa.
        }
    }
}
