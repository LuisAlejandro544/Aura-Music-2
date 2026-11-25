// =============================================================================
// AuraStreamCache.kt — Caché progresiva SimpleCache y enrutador de streams
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Gestiona el streaming progresivo ("escuchar mientras se descarga") con
//   Media3 ExoPlayer sin duplicar archivos locales en disco:
//   - Mantiene un único singleton `SimpleCache` (512 MB LRU) en
//     `cacheDir/aura_stream_cache` para guardar los fragmentos de audio conforme
//     ExoPlayer los reproduce.
//   - Conserva en memoria las URLs directas resueltas por `yt-dlp` junto con
//     sus `http_headers` exactos (`User-Agent`, etc.) y tiempo de expiración.
//   - Usa `ResolvingDataSource.Factory` + `CacheKeyFactory` estable
//     (`aura_yt_<videoId>`) para traducir URIs lógicas `aura-stream://` a la
//     URL CDN vigente justo cuando ExoPlayer abre el flujo en segundo plano,
//     permitiendo avance de cola automático sin resolver toda la lista antes.
//   - Enruta `file://` y `content://` directo a `DefaultDataSource` para no
//     cachear música local ya almacenada en el dispositivo.
// =============================================================================

package com.auramusic.player

import android.content.Context
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.CacheKeyFactory
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import java.io.File
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap

data class ResolvedStreamEntry(
    val videoId: String,
    val webpageUrl: String,
    val streamUrl: String,
    val httpHeaders: Map<String, String>,
    val mimeType: String,
    val ext: String,
    val abr: Int,
    val asr: Int,
    val durationMs: Long,
    val expiresAtMs: Long,
) {
    fun toMap(cachedBytes: Long = 0L): Map<String, Any?> = mapOf(
        "videoId" to videoId,
        "webpageUrl" to webpageUrl,
        "mimeType" to mimeType,
        "ext" to ext,
        "abr" to abr,
        "asr" to asr,
        "durationMs" to durationMs,
        "expiresAtMs" to expiresAtMs,
        "cachedBytes" to cachedBytes,
    )
}

@OptIn(UnstableApi::class)
object AuraStreamCache {

    private const val STREAM_CACHE_DIR = "aura_stream_cache"
    private const val MAX_CACHE_BYTES = 512L * 1024L * 1024L // 512 MB LRU
    private const val EXPIRY_SAFETY_MARGIN_MS = 90_000L

    @Volatile
    private var simpleCache: SimpleCache? = null
    private val cacheLock = Any()

    private val resolvedStreams = ConcurrentHashMap<String, ResolvedStreamEntry>()

    fun cacheKeyForVideoId(videoId: String): String = "aura_yt_$videoId"

    fun buildStreamUri(videoId: String, webpageUrl: String): String {
        return Uri.Builder()
            .scheme("aura-stream")
            .authority("track")
            .appendQueryParameter("id", videoId)
            .appendQueryParameter("u", webpageUrl)
            .build()
            .toString()
    }

    fun extractVideoIdFromUri(uri: Uri?): String {
        if (uri == null || uri.scheme != "aura-stream") return ""
        val qId = uri.getQueryParameter("id")?.trim().orEmpty()
        if (qId.isNotEmpty()) return qId
        return uri.lastPathSegment?.trim().orEmpty()
    }

    fun putResolvedStream(entry: ResolvedStreamEntry) {
        if (entry.videoId.isNotBlank()) {
            resolvedStreams[entry.videoId] = entry
        }
    }

    fun getValidResolvedStream(videoId: String): ResolvedStreamEntry? {
        if (videoId.isBlank()) return null
        val entry = resolvedStreams[videoId] ?: return null
        if (System.currentTimeMillis() >= entry.expiresAtMs - EXPIRY_SAFETY_MARGIN_MS) {
            resolvedStreams.remove(videoId)
            return null
        }
        return entry
    }

    fun invalidate(videoId: String) {
        if (videoId.isNotBlank()) {
            resolvedStreams.remove(videoId)
        }
    }

    fun getCache(context: Context): SimpleCache {
        simpleCache?.let { return it }
        synchronized(cacheLock) {
            simpleCache?.let { return it }
            val appContext = context.applicationContext
            val dir = File(appContext.cacheDir, STREAM_CACHE_DIR).apply {
                if (!exists()) mkdirs()
            }
            val dbProvider = StandaloneDatabaseProvider(appContext)
            val created = SimpleCache(
                dir,
                LeastRecentlyUsedCacheEvictor(MAX_CACHE_BYTES),
                dbProvider
            )
            simpleCache = created
            return created
        }
    }

    fun getCachedBytes(context: Context, videoId: String): Long {
        if (videoId.isBlank()) return 0L
        return runCatching {
            val cache = getCache(context)
            cache.getCachedBytes(cacheKeyForVideoId(videoId), 0L, C.LENGTH_UNSET.toLong())
        }.getOrDefault(0L)
    }

    fun getCacheStats(context: Context): Map<String, Any> {
        return runCatching {
            val cache = getCache(context)
            val usedBytes = cache.cacheSpace
            val cachedTracks = cache.keys.size
            mapOf(
                "usedBytes" to usedBytes,
                "maxBytes" to MAX_CACHE_BYTES,
                "cachedTracks" to cachedTracks
            )
        }.getOrDefault(
            mapOf(
                "usedBytes" to 0L,
                "maxBytes" to MAX_CACHE_BYTES,
                "cachedTracks" to 0
            )
        )
    }

    fun clearCache(context: Context): Map<String, Any> {
        resolvedStreams.clear()
        runCatching {
            val cache = getCache(context)
            val keys = cache.keys.toList()
            for (key in keys) {
                cache.removeResource(key)
            }
        }
        return getCacheStats(context)
    }

    fun createRoutingDataSourceFactory(context: Context): DataSource.Factory {
        val appContext = context.applicationContext

        val httpFactory = DefaultHttpDataSource.Factory()
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(25_000)
            .setAllowCrossProtocolRedirects(true)

        val resolvingHttpFactory = ResolvingDataSource.Factory(httpFactory) { dataSpec ->
            if (dataSpec.uri.scheme != "aura-stream") {
                return@Factory dataSpec
            }

            val videoId = extractVideoIdFromUri(dataSpec.uri)
            val rawWebpageUrl = dataSpec.uri.getQueryParameter("u")?.trim().orEmpty()
            val webpageUrl = rawWebpageUrl.ifEmpty {
                if (videoId.isNotEmpty()) "https://www.youtube.com/watch?v=$videoId" else ""
            }
            if (webpageUrl.isEmpty()) {
                throw IOException("Enlace de stream inválido para reproducción")
            }

            val entry = getValidResolvedStream(videoId) ?: try {
                AuraYtDownloader.resolveStreamBlocking(
                    context = appContext,
                    rawUrl = webpageUrl,
                    videoIdHint = videoId,
                    formatPref = "best"
                )
            } catch (err: Throwable) {
                throw IOException(err.message ?: "No se pudo conectar el flujo de audio", err)
            }

            val builder = dataSpec.buildUpon()
                .setUri(Uri.parse(entry.streamUrl))
            if (entry.httpHeaders.isNotEmpty()) {
                builder.setHttpRequestHeaders(entry.httpHeaders)
            }
            builder.build()
        }

        val auraCacheKeyFactory = CacheKeyFactory { dataSpec ->
            val explicitKey = dataSpec.key
            if (!explicitKey.isNullOrBlank()) {
                explicitKey
            } else if (dataSpec.uri.scheme == "aura-stream") {
                val vid = extractVideoIdFromUri(dataSpec.uri)
                if (vid.isNotEmpty()) cacheKeyForVideoId(vid)
                else CacheKeyFactory.DEFAULT.buildCacheKey(dataSpec)
            } else {
                CacheKeyFactory.DEFAULT.buildCacheKey(dataSpec)
            }
        }

        val localFactory = DefaultDataSource.Factory(appContext)

        return DataSource.Factory {
            val cacheFactory = CacheDataSource.Factory()
                .setCache(getCache(appContext))
                .setUpstreamDataSourceFactory(resolvingHttpFactory)
                .setCacheKeyFactory(auraCacheKeyFactory)
                .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)

            AuraRoutingDataSource(
                localDataSource = localFactory.createDataSource(),
                cacheDataSource = cacheFactory.createDataSource()
            )
        }
    }
}

@OptIn(UnstableApi::class)
private class AuraRoutingDataSource(
    private val localDataSource: DataSource,
    private val cacheDataSource: DataSource,
) : DataSource {

    private var activeDataSource: DataSource? = null

    override fun addTransferListener(transferListener: TransferListener) {
        localDataSource.addTransferListener(transferListener)
        cacheDataSource.addTransferListener(transferListener)
    }

    override fun open(dataSpec: DataSpec): Long {
        val scheme = dataSpec.uri.scheme?.lowercase().orEmpty()
        val target = if (scheme == "aura-stream" || scheme == "http" || scheme == "https") {
            cacheDataSource
        } else {
            localDataSource
        }
        activeDataSource = target
        return target.open(dataSpec)
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        return activeDataSource?.read(buffer, offset, length) ?: C.RESULT_END_OF_INPUT
    }

    override fun getUri(): Uri? = activeDataSource?.uri

    override fun getResponseHeaders(): Map<String, List<String>> =
        activeDataSource?.responseHeaders ?: emptyMap()

    override fun close() {
        try {
            activeDataSource?.close()
        } finally {
            activeDataSource = null
        }
    }
}
