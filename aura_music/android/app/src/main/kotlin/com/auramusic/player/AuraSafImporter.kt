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
import java.util.concurrent.atomic.AtomicInteger

class AuraSafImporter(
    private val activity: Activity,
    private val scope: CoroutineScope,
    private val onProgress: (processed: Int, total: Int) -> Unit
) {
    companion object {
        const val REQUEST_PICK_AUDIO_FILES = 4101
        const val REQUEST_PICK_AUDIO_FOLDER = 4102
        private const val MAX_FOLDER_DEPTH = 32

        private val SUPPORTED_EXTENSIONS = setOf(
            "mp3", "flac", "m4a", "aac", "wav", "ogg", "opus", "alac", "wma"
        )
    }

    private var pendingCallback: ((Result<List<AuraTrackMetadata>>) -> Unit)? = null

    fun launchPickAudioFiles(callback: (Result<List<AuraTrackMetadata>>) -> Unit) {
        pendingCallback?.invoke(Result.success(emptyList()))
        pendingCallback = callback
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "audio/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, REQUEST_PICK_AUDIO_FILES)
        } catch (err: Exception) {
            val active = pendingCallback
            pendingCallback = null
            active?.invoke(Result.failure(err))
        }
    }

    fun launchPickAudioFolder(callback: (Result<List<AuraTrackMetadata>>) -> Unit) {
        pendingCallback?.invoke(Result.success(emptyList()))
        pendingCallback = callback
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            activity.startActivityForResult(intent, REQUEST_PICK_AUDIO_FOLDER)
        } catch (err: Exception) {
            val active = pendingCallback
            pendingCallback = null
            active?.invoke(Result.failure(err))
        }
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

                val distinctUris = uris.distinctBy { it.toString() }
                scope.launch {
                    val result = runCatching { processSelectedFiles(distinctUris) }
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
            if (total == 0) return@withContext emptyList()

            val processed = AtomicInteger(0)
            val gate = Semaphore(4)
            withContext(Dispatchers.Main) { onProgress(0, total) }

            val jobs = uris.map { uri ->
                async {
                    val meta = gate.withPermit {
                        takePersistablePermissionSafe(uri)
                        AuraMetadataExtractor.extract(
                            context = activity.applicationContext,
                            uri = uri,
                            folderName = "Pistas Importadas"
                        )
                    }
                    // Incrementa y notifica en el hilo principal para mantener orden monótono 1..total
                    withContext(Dispatchers.Main) {
                        onProgress(processed.incrementAndGet(), total)
                    }
                    meta
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
            val visitedUris = HashSet<String>()
            collectAudioDocuments(rootDoc, rootFolderName, audioDocs, visitedUris, depth = 0)

            val total = audioDocs.size
            if (total == 0) return@withContext emptyList()

            val processed = AtomicInteger(0)
            val gate = Semaphore(4)
            withContext(Dispatchers.Main) { onProgress(0, total) }

            val jobs = audioDocs.map { (doc, folderLabel) ->
                async {
                    val meta = gate.withPermit {
                        AuraMetadataExtractor.extract(
                            context = activity.applicationContext,
                            uri = doc.uri,
                            folderName = folderLabel,
                            fallbackDisplayName = doc.name
                        )
                    }
                    withContext(Dispatchers.Main) {
                        onProgress(processed.incrementAndGet(), total)
                    }
                    meta
                }
            }
            jobs.awaitAll().filterNotNull()
        }

    private fun collectAudioDocuments(
        dir: DocumentFile,
        folderName: String,
        output: MutableList<Pair<DocumentFile, String>>,
        visitedUris: MutableSet<String>,
        depth: Int
    ) {
        if (depth > MAX_FOLDER_DEPTH) return
        val dirKey = dir.uri.toString()
        if (!visitedUris.add(dirKey)) return

        val children = try {
            dir.listFiles()
        } catch (_: Exception) {
            emptyArray()
        }
        for (child in children) {
            if (child.isDirectory) {
                collectAudioDocuments(
                    dir = child,
                    folderName = child.name ?: folderName,
                    output = output,
                    visitedUris = visitedUris,
                    depth = depth + 1
                )
            } else if (child.isFile && isSupportedAudio(child)) {
                if (visitedUris.add(child.uri.toString())) {
                    output.add(child to folderName)
                }
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
