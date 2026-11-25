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
            emitEvent(
                mapOf(
                    "type" to "error",
                    "message" to (error.localizedMessage ?: "No se pudo reproducir el archivo de audio")
                )
            )
        }
    }

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
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
            val file = File(artworkPath)
            if (file.exists()) {
                metaBuilder.setArtworkUri(Uri.fromFile(file))
            }
        }

        return MediaItem.Builder()
            .setMediaId(id)
            .setUri(Uri.parse(uri))
            .setMediaMetadata(metaBuilder.build())
            .build()
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
                "playbackState" to controller.playbackState,
                "currentIndex" to controller.currentMediaItemIndex,
                "currentMediaId" to controller.currentMediaItem?.mediaId,
                "positionMs" to controller.currentPosition.coerceAtLeast(0L),
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
        mainHandler.removeCallbacks(positionTicker)
        mediaController?.removeListener(playerListener)
        controllerFuture?.let { MediaController.releaseFuture(it) }
        bridgeScope.cancel()
    }
}
