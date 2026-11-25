// =============================================================================
// AuraAudioBridge.kt — Puente nativo Flutter <-> Media3 ExoPlayer + SAF
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Conecta la interfaz en Flutter (Dart) con AuraPlaybackService (ExoPlayer)
//   y AuraSafImporter usando MethodChannel + EventChannel.
//   - Se conecta de forma asíncrona al MediaSessionService para NO retrasar el
//     arranque inicial de la app.
//   - Emite eventos de estado (posición, duración, reproducción, pista actual,
//     progreso de importación) únicamente cuando hay cambios o durante la
//     reproducción activa.
// =============================================================================

package com.auramusic.player

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

class AuraAudioBridge(
    private val activity: Activity,
    messenger: BinaryMessenger
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL = "com.auramusic.player/audio"
        private const val EVENT_CHANNEL = "com.auramusic.player/events"
    }

    private val methodChannel = MethodChannel(messenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(messenger, EVENT_CHANNEL)
    private val bridgeScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eventSink: EventChannel.EventSink? = null
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var mediaController: MediaController? = null

    private val safImporter = AuraSafImporter(
        activity = activity,
        scope = bridgeScope,
        onProgress = { processed, total ->
            emitEvent(
                mapOf(
                    "type" to "importProgress",
                    "processed" to processed,
                    "total" to total
                )
            )
        }
    )

    private val positionTicker = object : Runnable {
        override fun run() {
            val controller = mediaController
            if (controller != null && controller.isPlaying) {
                emitPlaybackState(controller)
                mainHandler.postDelayed(this, 250L)
            }
        }
    }

    private val playerListener = object : Player.Listener {
        override fun onIsPlayingChanged(isPlaying: Boolean) {
            mediaController?.let { emitPlaybackState(it) }
            mainHandler.removeCallbacks(positionTicker)
            if (isPlaying) {
                mainHandler.post(positionTicker)
            }
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            mediaController?.let { emitPlaybackState(it) }
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            mediaController?.let { emitPlaybackState(it) }
        }

        override fun onRepeatModeChanged(repeatMode: Int) {
            mediaController?.let { emitPlaybackState(it) }
        }

        override fun onShuffleModeEnabledChanged(shuffleModeEnabled: Boolean) {
            mediaController?.let { emitPlaybackState(it) }
        }

        override fun onPlayerError(error: PlaybackException) {
            val currentUri = mediaController?.currentMediaItem?.localConfiguration?.uri
            if (currentUri?.scheme == "aura-stream") {
                val vid = AuraStreamCache.extractVideoIdFromUri(currentUri)
                AuraStreamCache.invalidate(vid)
            }
            emitEvent(
                mapOf(
                    "type" to "error",
                    "message" to (error.localizedMessage ?: "No se pudo reproducir el audio")
                )
            )
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        AuraRustDspBridge.onSpatial8dRouteChanged = { stateMap ->
            emitEvent(mapOf("type" to "spatial8dState") + stateMap)
        }
    }

    /**
     * Inicia la conexión al MediaSessionService de forma diferida y asíncrona
     * para garantizar un arranque instantáneo de Flutter.
     */
    fun ensureControllerConnected(onReady: (() -> Unit)? = null) {
        if (mediaController != null) {
            onReady?.invoke()
            return
        }
        val appContext = activity.applicationContext
        val token = SessionToken(appContext, ComponentName(appContext, AuraPlaybackService::class.java))
        val future = MediaController.Builder(appContext, token).buildAsync()
        controllerFuture = future

        future.addListener({
            try {
                val controller = future.get()
                mediaController = controller
                controller.addListener(playerListener)
                emitPlaybackState(controller)
                onReady?.invoke()
            } catch (e: Exception) {
                emitEvent(
                    mapOf(
                        "type" to "error",
                        "message" to "Error conectando motor ExoPlayer: ${e.localizedMessage}"
                    )
                )
            }
        }, ContextCompat.getMainExecutor(appContext))
    }

    fun handleActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        return safImporter.handleActivityResult(requestCode, resultCode, data)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initEngine" -> {
                ensureControllerConnected {
                    result.success(mapOf("engine" to "media3-exoplayer", "ready" to true))
                }
            }

            "pickAudioFiles" -> {
                safImporter.launchPickAudioFiles { outcome ->
                    outcome.fold(
                        onSuccess = { list -> result.success(list.map { it.toMap() }) },
                        onFailure = { err -> result.error("IMPORT_ERR", err.message, null) }
                    )
                }
            }

            "pickAudioFolder" -> {
                safImporter.launchPickAudioFolder { outcome ->
                    outcome.fold(
                        onSuccess = { list -> result.success(list.map { it.toMap() }) },
                        onFailure = { err -> result.error("IMPORT_ERR", err.message, null) }
                    )
                }
            }

            "setQueueAndPlay" -> {
                val rawTracks = call.argument<List<Map<String, Any?>>>("tracks") ?: emptyList()
                val startIndex = call.argument<Int>("startIndex") ?: 0
                val autoPlay = call.argument<Boolean>("autoPlay") ?: true
                val startPositionMs = (call.argument<Number>("startPositionMs")?.toLong()) ?: 0L

                ensureControllerConnected {
                    val controller = mediaController
                    if (controller == null) {
                        result.error("NO_CONTROLLER", "ExoPlayer no disponible", null)
                        return@ensureControllerConnected
                    }
                    val items = rawTracks.map { buildMediaItem(it) }
                    controller.setMediaItems(items, startIndex.coerceIn(0, (items.size - 1).coerceAtLeast(0)), startPositionMs)
                    controller.prepare()
                    controller.playWhenReady = autoPlay
                    result.success(true)
                }
            }

            "addToQueue" -> {
                val trackMap = call.argument<Map<String, Any?>>("track")
                val insertIndex = call.argument<Int>("insertIndex")
                if (trackMap == null) {
                    result.error("INVALID_ARG", "Pista inválida para encolar", null)
                    return
                }
                ensureControllerConnected {
                    val controller = mediaController
                    if (controller == null) {
                        result.error("NO_CONTROLLER", "ExoPlayer no disponible", null)
                        return@ensureControllerConnected
                    }
                    val item = buildMediaItem(trackMap)
                    if (controller.mediaItemCount == 0) {
                        controller.setMediaItem(item)
                        controller.prepare()
                        controller.playWhenReady = true
                    } else if (insertIndex != null) {
                        val safeIndex = insertIndex.coerceIn(0, controller.mediaItemCount)
                        controller.addMediaItem(safeIndex, item)
                    } else {
                        controller.addMediaItem(item)
                    }
                    emitPlaybackState(controller)
                    result.success(true)
                }
            }

            "moveQueueItem" -> {
                val fromIndex = call.argument<Int>("fromIndex") ?: -1
                val toIndex = call.argument<Int>("toIndex") ?: -1
                val controller = mediaController
                if (controller != null &&
                    fromIndex in 0 until controller.mediaItemCount &&
                    toIndex in 0 until controller.mediaItemCount &&
                    fromIndex != toIndex
                ) {
                    controller.moveMediaItem(fromIndex, toIndex)
                    emitPlaybackState(controller)
                }
                result.success(true)
            }

            "removeQueueItem" -> {
                val index = call.argument<Int>("index") ?: -1
                val controller = mediaController
                if (controller != null && index in 0 until controller.mediaItemCount) {
                    controller.removeMediaItem(index)
                    if (controller.mediaItemCount == 0) {
                        controller.stop()
                    }
                    emitPlaybackState(controller)
                }
                result.success(true)
            }

            "play" -> {
                ensureControllerConnected {
                    mediaController?.play()
                    result.success(true)
                }
            }

            "pause" -> {
                mediaController?.pause()
                result.success(true)
            }

            "seekTo" -> {
                val positionMs = call.argument<Number>("positionMs")?.toLong() ?: 0L
                mediaController?.seekTo(positionMs)
                mediaController?.let { emitPlaybackState(it) }
                result.success(true)
            }

            "skipNext" -> {
                mediaController?.seekToNextMediaItem()
                result.success(true)
            }

            "skipPrevious" -> {
                val controller = mediaController
                if (controller != null) {
                    if (controller.currentPosition > 3500L) {
                        controller.seekTo(0L)
                    } else {
                        controller.seekToPreviousMediaItem()
                    }
                }
                result.success(true)
            }

            "skipToIndex" -> {
                val index = call.argument<Int>("index") ?: 0
                mediaController?.seekToDefaultPosition(index)
                mediaController?.play()
                result.success(true)
            }

            "setShuffle" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                mediaController?.shuffleModeEnabled = enabled
                result.success(true)
            }

            "setRepeatMode" -> {
                val mode = call.argument<String>("mode") ?: "off"
                val exoMode = when (mode) {
                    "all" -> Player.REPEAT_MODE_ALL
                    "one" -> Player.REPEAT_MODE_ONE
                    else -> Player.REPEAT_MODE_OFF
                }
                mediaController?.repeatMode = exoMode
                result.success(true)
            }

            "convertImageToLosslessWebp" -> {
                val sourcePath = call.argument<String>("sourcePath")
                val trackId = call.argument<String>("trackId") ?: "track"
                if (sourcePath.isNullOrBlank()) {
                    result.error("INVALID_ARG", "Ruta de imagen inválida", null)
                    return
                }
                bridgeScope.launch {
                    runCatching {
                        AuraArtworkProcessor.convertToLosslessWebp(
                            context = activity.applicationContext,
                            sourcePath = sourcePath,
                            trackId = trackId
                        )
                    }.fold(
                        onSuccess = { info -> result.success(info.toMap()) },
                        onFailure = { err -> result.error("WEBP_ERR", err.message, null) }
                    )
                }
            }

            "commitCustomArtwork" -> {
                val pendingPath = call.argument<String>("pendingPath")
                val trackId = call.argument<String>("trackId") ?: "track"
                if (pendingPath.isNullOrBlank()) {
                    result.error("INVALID_ARG", "Ruta WebP pendiente inválida", null)
                    return
                }
                bridgeScope.launch {
                    runCatching {
                        AuraArtworkProcessor.commitCustomArtwork(
                            context = activity.applicationContext,
                            pendingOrExistingPath = pendingPath,
                            trackId = trackId
                        )
                    }.fold(
                        onSuccess = { path -> result.success(path) },
                        onFailure = { err -> result.error("ART_COMMIT_ERR", err.message, null) }
                    )
                }
            }

            "deleteCustomArtworks" -> {
                val trackId = call.argument<String>("trackId")
                if (trackId.isNullOrBlank()) {
                    result.success(true)
                    return
                }
                bridgeScope.launch {
                    runCatching {
                        AuraArtworkProcessor.deleteCustomArtworksForTrack(
                            context = activity.applicationContext,
                            trackId = trackId
                        )
                    }
                    result.success(true)
                }
            }

            "deleteTrackResources" -> {
                val trackId = call.argument<String>("trackId") ?: ""
                val trackUri = call.argument<String>("trackUri") ?: ""
                bridgeScope.launch {
                    withContext(Dispatchers.IO) {
                        val appContext = activity.applicationContext
                        if (trackId.isNotBlank()) {
                            runCatching {
                                AuraArtworkProcessor.deleteCustomArtworksForTrack(
                                    context = appContext,
                                    trackId = trackId
                                )
                            }
                            runCatching {
                                val cachedThumb = File(File(appContext.cacheDir, "artworks"), "$trackId.jpg")
                                if (cachedThumb.exists()) cachedThumb.delete()
                            }
                        }
                        if (trackUri.isNotBlank()) {
                            runCatching {
                                val parsed = Uri.parse(trackUri)
                                if (parsed.scheme == "file" && !parsed.path.isNullOrBlank()) {
                                    val downloadsRoot = File(appContext.filesDir, "aura_downloads").canonicalFile
                                    val targetFile = File(parsed.path!!).canonicalFile
                                    // Solo borra archivos físicos descargados dentro del directorio privado aura_downloads
                                    if (targetFile.path.startsWith(downloadsRoot.path + File.separator) && targetFile.exists()) {
                                        targetFile.delete()
                                    }
                                }
                            }
                        }
                    }
                    result.success(true)
                }
            }

            "updateMediaItemMetadata" -> {
                val trackMap = call.argument<Map<String, Any?>>("track")
                val trackId = trackMap?.get("id") as? String
                val controller = mediaController
                if (trackMap != null && !trackId.isNullOrBlank() && controller != null) {
                    val updatedItem = buildMediaItem(trackMap)
                    val count = controller.mediaItemCount
                    for (i in 0 until count) {
                        if (controller.getMediaItemAt(i).mediaId == trackId) {
                            controller.replaceMediaItem(i, updatedItem)
                        }
                    }
                }
                result.success(true)
            }

            "getYtEngineStatus" -> {
                val includePython = call.argument<Boolean>("includePython") ?: false
                bridgeScope.launch {
                    runCatching {
                        AuraYtDownloader.getEngineStatus(
                            context = activity.applicationContext,
                            includePython = includePython
                        )
                    }.fold(
                        onSuccess = { status -> result.success(status) },
                        onFailure = { err -> result.error("YT_STATUS_ERR", err.message, null) }
                    )
                }
            }

            "checkYtEngineUpdates" -> {
                bridgeScope.launch {
                    runCatching {
                        AuraYtDownloader.checkUpdates(activity.applicationContext)
                    }.fold(
                        onSuccess = { info -> result.success(info) },
                        onFailure = { err -> result.error("YT_UPDATE_CHECK_ERR", err.message, null) }
                    )
                }
            }

            "updateYtEngine" -> {
                val force = call.argument<Boolean>("force") ?: false
                bridgeScope.launch {
                    runCatching {
                        AuraYtDownloader.updatePackages(
                            context = activity.applicationContext,
                            force = force,
                            onProgress = { stage, packageName, percent, downloadedBytes, totalBytes, message ->
                                emitEvent(
                                    mapOf(
                                        "type" to "ytUpdateProgress",
                                        "stage" to stage,
                                        "packageName" to packageName,
                                        "percent" to percent,
                                        "downloadedBytes" to downloadedBytes,
                                        "totalBytes" to totalBytes,
                                        "message" to message
                                    )
                                )
                            }
                        )
                    }.fold(
                        onSuccess = { res -> result.success(res) },
                        onFailure = { err -> result.error("YT_UPDATE_ERR", err.message, null) }
                    )
                }
            }

            "setYtAutoUpdateEnabled" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                bridgeScope.launch {
                    runCatching {
                        AuraYtDownloader.setAutoUpdateEnabled(activity.applicationContext, enabled)
                    }.fold(
                        onSuccess = { value -> result.success(value) },
                        onFailure = { err -> result.error("YT_PREF_ERR", err.message, null) }
                    )
                }
            }

            "restoreBundledYtEngine" -> {
                bridgeScope.launch {
                    runCatching {
                        AuraYtDownloader.restoreBundledEngine(activity.applicationContext)
                    }.fold(
                        onSuccess = { res -> result.success(res) },
                        onFailure = { err -> result.error("YT_RESTORE_ERR", err.message, null) }
                    )
                }
            }

            "downloadFromUrl" -> {
                val url = call.argument<String>("url")
                val formatPref = call.argument<String>("format") ?: "best"
                if (url.isNullOrBlank()) {
                    result.error("INVALID_ARG", "La URL no puede estar vacía", null)
                    return
                }
                bridgeScope.launch {
                    runCatching {
                        AuraYtDownloader.downloadTrackFromUrl(
                            context = activity.applicationContext,
                            rawUrl = url,
                            formatPref = formatPref,
                            onProgress = { stage, percent, downloadedBytes, totalBytes, message ->
                                emitEvent(
                                    mapOf(
                                        "type" to "downloadProgress",
                                        "stage" to stage,
                                        "percent" to percent,
                                        "downloadedBytes" to downloadedBytes,
                                        "totalBytes" to totalBytes,
                                        "message" to message
                                    )
                                )
                            }
                        )
                    }.fold(
                        onSuccess = { meta -> result.success(meta.toMap()) },
                        onFailure = { err ->
                            val rawDetail = when (err) {
                                is YtDownloadDetailedException -> err.rawDetail
                                else -> err.stackTraceToString()
                            }
                            result.error(
                                "YT_DOWNLOAD_ERR",
                                err.message ?: "Error al descargar desde URL",
                                rawDetail
                            )
                        }
                    )
                }
            }

            "getEqualizerState" -> {
                bridgeScope.launch {
                    val state = withContext(Dispatchers.IO) {
                        AuraRustDspBridge.getStateMap(activity.applicationContext)
                    }
                    result.success(state)
                }
            }

            "updateEqualizerState" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val presetId = call.argument<String>("presetId") ?: "flat"
                val preampDb = (call.argument<Number>("preampDb")?.toFloat()) ?: 0f
                val limiterEnabled = call.argument<Boolean>("limiterEnabled") ?: true
                val rawBands = call.argument<List<Number>>("bandGainsDb") ?: emptyList()
                val bands = rawBands.map { it.toDouble() }
                bridgeScope.launch {
                    val state = withContext(Dispatchers.IO) {
                        AuraRustDspBridge.updateSettings(
                            context = activity.applicationContext,
                            enabled = enabled,
                            presetId = presetId,
                            preampDb = preampDb,
                            limiterEnabled = limiterEnabled,
                            bandGainsDb = bands
                        )
                    }
                    result.success(state)
                }
            }

            "getSpatial8dState" -> {
                bridgeScope.launch {
                    val state = withContext(Dispatchers.IO) {
                        AuraRustDspBridge.getSpatial8dStateMap(activity.applicationContext)
                    }
                    result.success(state)
                }
            }

            "updateSpatial8dState" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                val mode = call.argument<String>("mode") ?: "auto"
                val speedHz = (call.argument<Number>("speedHz")?.toFloat()) ?: 0.16f
                val intensity = (call.argument<Number>("intensity")?.toFloat()) ?: 0.75f
                bridgeScope.launch {
                    val state = withContext(Dispatchers.IO) {
                        AuraRustDspBridge.updateSpatial8dSettings(
                            context = activity.applicationContext,
                            enabled = enabled,
                            mode = mode,
                            speedHz = speedHz,
                            intensity = intensity
                        )
                    }
                    result.success(state)
                }
            }

            "searchExplore" -> {
                val query = call.argument<String>("query") ?: ""
                val limit = call.argument<Int>("limit") ?: 18
                bridgeScope.launch {
                    runCatching {
                        AuraYtDownloader.searchExplore(
                            context = activity.applicationContext,
                            queryOrUrl = query,
                            limit = limit
                        )
                    }.fold(
                        onSuccess = { payload -> result.success(payload) },
                        onFailure = { err ->
                            val rawDetail = when (err) {
                                is YtDownloadDetailedException -> err.rawDetail
                                else -> err.stackTraceToString()
                            }
                            result.error(
                                "YT_EXPLORE_ERR",
                                err.message ?: "Error al explorar música",
                                rawDetail
                            )
                        }
                    )
                }
            }

            "fetchExploreRecommendations" -> {
                val tastePayloadJson = call.argument<String>("tastePayloadJson") ?: "{}"
                val limit = call.argument<Int>("limit") ?: 16
                bridgeScope.launch {
                    runCatching {
                        AuraYtDownloader.fetchExploreRecommendations(
                            context = activity.applicationContext,
                            tastePayloadJson = tastePayloadJson,
                            limit = limit
                        )
                    }.fold(
                        onSuccess = { payload -> result.success(payload) },
                        onFailure = { err ->
                            val rawDetail = when (err) {
                                is YtDownloadDetailedException -> err.rawDetail
                                else -> err.stackTraceToString()
                            }
                            result.error(
                                "YT_RECOMMEND_ERR",
                                err.message ?: "Error al generar recomendaciones",
                                rawDetail
                            )
                        }
                    )
                }
            }

            "resolveExploreStream" -> {
                val url = call.argument<String>("url") ?: ""
                val videoId = call.argument<String>("videoId") ?: ""
                val formatPref = call.argument<String>("format") ?: "best"
                if (url.isBlank()) {
                    result.error("INVALID_ARG", "La URL del stream no puede estar vacía", null)
                    return
                }
                bridgeScope.launch {
                    runCatching {
                        val appContext = activity.applicationContext
                        val entry = AuraYtDownloader.resolveAudioStream(
                            context = appContext,
                            rawUrl = url,
                            videoIdHint = videoId,
                            formatPref = formatPref
                        )
                        val cachedBytes = AuraStreamCache.getCachedBytes(appContext, entry.videoId)
                        entry.toMap(cachedBytes)
                    }.fold(
                        onSuccess = { map -> result.success(map) },
                        onFailure = { err ->
                            val rawDetail = when (err) {
                                is YtDownloadDetailedException -> err.rawDetail
                                else -> err.stackTraceToString()
                            }
                            result.error(
                                "YT_STREAM_ERR",
                                err.message ?: "Error al conectar el flujo de audio",
                                rawDetail
                            )
                        }
                    )
                }
            }

            "getStreamCacheStats" -> {
                bridgeScope.launch {
                    val stats = withContext(Dispatchers.IO) {
                        AuraStreamCache.getCacheStats(activity.applicationContext)
                    }
                    result.success(stats)
                }
            }

            "clearStreamCache" -> {
                bridgeScope.launch {
                    val stats = withContext(Dispatchers.IO) {
                        AuraStreamCache.clearCache(activity.applicationContext)
                    }
                    result.success(stats)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun buildMediaItem(map: Map<String, Any?>): MediaItem {
        val id = map["id"] as? String ?: ""
        val uri = map["uri"] as? String ?: ""
        val title = map["title"] as? String ?: "Pista"
        val artist = map["artist"] as? String ?: "Artista desconocido"
        val album = map["album"] as? String ?: ""
        val artworkPath = map["artworkPath"] as? String

        val metaBuilder = MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .setAlbumTitle(album)

        if (!artworkPath.isNullOrBlank()) {
            if (artworkPath.startsWith("http://") || artworkPath.startsWith("https://")) {
                metaBuilder.setArtworkUri(Uri.parse(artworkPath))
            } else {
                val file = File(artworkPath)
                if (file.exists()) {
                    metaBuilder.setArtworkUri(Uri.fromFile(file))
                }
            }
        }

        val parsedUri = Uri.parse(uri)
        val itemBuilder = MediaItem.Builder()
            .setMediaId(id)
            .setUri(parsedUri)
            .setMediaMetadata(metaBuilder.build())

        if (parsedUri.scheme == "aura-stream") {
            val vid = AuraStreamCache.extractVideoIdFromUri(parsedUri)
            if (vid.isNotEmpty()) {
                itemBuilder.setCustomCacheKey(AuraStreamCache.cacheKeyForVideoId(vid))
            }
        }

        return itemBuilder.build()
    }

    private fun emitPlaybackState(controller: MediaController) {
        val repeatStr = when (controller.repeatMode) {
            Player.REPEAT_MODE_ALL -> "all"
            Player.REPEAT_MODE_ONE -> "one"
            else -> "off"
        }
        emitEvent(
            mapOf(
                "type" to "playbackState",
                "isPlaying" to controller.isPlaying,
                "isBuffering" to (controller.playbackState == Player.STATE_BUFFERING),
                "playbackState" to controller.playbackState,
                "currentIndex" to controller.currentMediaItemIndex,
                "currentMediaId" to controller.currentMediaItem?.mediaId,
                "positionMs" to controller.currentPosition.coerceAtLeast(0L),
                "bufferedPositionMs" to controller.bufferedPosition.coerceAtLeast(0L),
                "durationMs" to controller.duration.coerceAtLeast(0L),
                "shuffleEnabled" to controller.shuffleModeEnabled,
                "repeatMode" to repeatStr
            )
        )
    }

    private fun emitEvent(payload: Map<String, Any?>) {
        mainHandler.post {
            eventSink?.success(payload)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        mediaController?.let { emitPlaybackState(it) }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        AuraRustDspBridge.onSpatial8dRouteChanged = null
        mainHandler.removeCallbacks(positionTicker)
        mediaController?.removeListener(playerListener)
        controllerFuture?.let { MediaController.releaseFuture(it) }
        bridgeScope.cancel()
    }
}
