// =============================================================================
// AuraPlaybackService.kt — Servicio nativo de reproducción Media3 ExoPlayer
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Mantiene vivo el motor ExoPlayer dentro de un MediaSessionService para que
//   la música continúe sonando con fluidez aunque la usuaria minimice Aura Music
//   o apague la pantalla, mostrando controles multimedia en el panel de
//   notificaciones y pantalla bloqueada (Android 9+).
//
// Características integradas:
//   - AudioAttributes de tipo música con manejo automático de Audio Focus.
//   - Pausa automática al desconectar auriculares (handleAudioBecomingNoisy).
//   - Arquitectura con `AuraRustDspProcessor` en Rust (EQ 5 bandas + Audio 8D)
//     y `AuraStreamCache` (`SimpleCache` + `ResolvingDataSource`) para escuchar
//     música en streaming mientras se descarga progresivamente en caché.
// =============================================================================

package com.auramusic.player

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

@OptIn(UnstableApi::class)
class AuraPlaybackService : MediaSessionService() {

    private var mediaSession: MediaSession? = null
    private var exoPlayer: ExoPlayer? = null
    private val dspProcessor = AuraRustDspProcessor()
    private var audioManager: AudioManager? = null

    private val audioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
            AuraRustDspBridge.syncOutputRoute(applicationContext)
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
            AuraRustDspBridge.syncOutputRoute(applicationContext)
        }
    }

    override fun onCreate() {
        super.onCreate()
        AuraRustDspBridge.loadSavedSettings(applicationContext)
        audioManager = (getSystemService(Context.AUDIO_SERVICE) as? AudioManager)?.also { manager ->
            manager.registerAudioDeviceCallback(audioDeviceCallback, null)
        }

        val audioAttributes = AudioAttributes.Builder()
            .setUsage(C.USAGE_MEDIA)
            .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
            .build()

        val renderersFactory = object : DefaultRenderersFactory(this) {
            override fun buildAudioSink(
                context: Context,
                enableFloatOutput: Boolean,
                enableAudioTrackPlaybackParams: Boolean
            ): AudioSink {
                return DefaultAudioSink.Builder(context)
                    .setEnableFloatOutput(enableFloatOutput)
                    .setEnableAudioTrackPlaybackParams(enableAudioTrackPlaybackParams)
                    .setAudioProcessors(arrayOf(dspProcessor))
                    .build()
            }
        }

        val loadControl = DefaultLoadControl.Builder()
            .setBufferDurationsMs(
                /* minBufferMs = */ 15_000,
                /* maxBufferMs = */ 180_000,
                /* bufferForPlaybackMs = */ 1_500,
                /* bufferForPlaybackAfterRebufferMs = */ 3_000
            )
            .build()

        val mediaSourceFactory = DefaultMediaSourceFactory(
            AuraStreamCache.createRoutingDataSourceFactory(applicationContext)
        )

        val player = ExoPlayer.Builder(this, renderersFactory)
            .setMediaSourceFactory(mediaSourceFactory)
            .setLoadControl(loadControl)
            .setAudioAttributes(audioAttributes, /* handleAudioFocus = */ true)
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_LOCAL)
            .build()

        exoPlayer = player

        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val sessionActivityPendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        mediaSession = MediaSession.Builder(this, player)
            .setSessionActivity(sessionActivityPendingIntent)
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
        return mediaSession
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        val player = mediaSession?.player
        if (player == null || !player.playWhenReady || player.playbackState == Player.STATE_IDLE) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        audioManager?.unregisterAudioDeviceCallback(audioDeviceCallback)
        audioManager = null
        mediaSession?.run {
            player.release()
            release()
            mediaSession = null
        }
        exoPlayer = null
        super.onDestroy()
    }
}
