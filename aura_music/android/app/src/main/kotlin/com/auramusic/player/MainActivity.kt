// =============================================================================
// MainActivity.kt — Punto de entrada Android de Aura Music
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Registra AuraAudioBridge dentro del FlutterEngine tan pronto arranca la
//   actividad y delega los resultados de los selectores SAF de archivos/carpetas.
//   Mantiene configureFlutterEngine ligero para garantizar una apertura rápida.
// =============================================================================

package com.auramusic.player

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var audioBridge: AuraAudioBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        audioBridge = AuraAudioBridge(
            activity = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (audioBridge?.handleActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        audioBridge?.dispose()
        audioBridge = null
        super.onDestroy()
    }
}
