// =============================================================================
// settings_provider.dart — Estado de Configuración, Tema y Auto-actualizador
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Gestiona de forma modular y persistente las preferencias de Aura Music:
//   1. Modo de apariencia (Claro, Oscuro o Sistema) guardado en SharedPreferences
//      con Modo Claro como valor por defecto.
//   2. Estado vivo de versiones nativas (yt-dlp, yt-dlp-ejs, Python, Rust
//      QuickJS-ng, Rust Lofty y Rust DSP aura_dsp).
//   3. Control del auto-actualizador PyPI de yt-dlp y yt-dlp-ejs (activar/
//      desactivar chequeo automático, buscar actualizaciones, aplicarlas con
//      progreso en tiempo real y restaurar la versión incluida en el APK).
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/audio/audio_engine_port.dart';
import '../core/models/audio_track.dart';

class SettingsProvider extends ChangeNotifier {
  SettingsProvider({required AudioEnginePort engine}) : _engine = engine {
    _progressSub = _engine.ytUpdateProgressEvents.listen((event) {
      _updateProgress = event;
      notifyListeners();
    });
  }

  static const String _prefThemeMode = 'aura_theme_mode';

  final AudioEnginePort _engine;
  StreamSubscription<YtUpdateProgressEvent>? _progressSub;

  ThemeMode _themeMode = ThemeMode.light;
  bool _themeHydrated = false;

  YtEngineStatus? _engineStatus;
  EqualizerState? _equalizerState;
  YtUpdateCheckResult? _lastCheckResult;
  YtUpdateProgressEvent? _updateProgress;

  bool _isLoadingStatus = false;
  bool _isCheckingUpdates = false;
  bool _isUpdatingEngine = false;
  bool _isRestoringEngine = false;

  String? _statusMessage;
  String? _errorMessage;

  ThemeMode get themeMode => _themeMode;
  bool get themeHydrated => _themeHydrated;
  YtEngineStatus? get engineStatus => _engineStatus;
  EqualizerState? get equalizerState => _equalizerState;
  YtUpdateCheckResult? get lastCheckResult => _lastCheckResult;
  YtUpdateProgressEvent? get updateProgress => _updateProgress;

  bool get isLoadingStatus => _isLoadingStatus;
  bool get isCheckingUpdates => _isCheckingUpdates;
  bool get isUpdatingEngine => _isUpdatingEngine;
  bool get isRestoringEngine => _isRestoringEngine;
  bool get isBusy =>
      _isLoadingStatus ||
      _isCheckingUpdates ||
      _isUpdatingEngine ||
      _isRestoringEngine;

  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;

  Future<void> hydrateThemeMode() async {
    if (_themeHydrated) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefThemeMode) ?? 'light';
      _themeMode = switch (raw) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      };
    } catch (_) {
      _themeMode = ThemeMode.light;
    } finally {
      _themeHydrated = true;
      notifyListeners();
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final serialized = switch (mode) {
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
        ThemeMode.light => 'light',
      };
      await prefs.setString(_prefThemeMode, serialized);
    } catch (_) {
      // No bloquear la UI si SharedPreferences falla
    }
  }

  Future<void> loadEngineDetails({bool includePython = true}) async {
    _isLoadingStatus = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait<dynamic>([
        _engine.getYtEngineStatus(includePython: includePython),
        _engine.getEqualizerState(),
      ]);
      _engineStatus = results[0] as YtEngineStatus;
      _equalizerState = results[1] as EqualizerState;
    } catch (err) {
      _errorMessage = 'No se pudo consultar el estado del motor: $err';
    } finally {
      _isLoadingStatus = false;
      notifyListeners();
    }
  }

  Future<void> toggleAutoUpdate(bool enabled) async {
    _errorMessage = null;
    try {
      final saved = await _engine.setYtAutoUpdateEnabled(enabled);
      final current = _engineStatus;
      if (current != null) {
        _engineStatus = YtEngineStatus(
          pythonStarted: current.pythonStarted,
          pythonVersion: current.pythonVersion,
          ytDlpVersion: current.ytDlpVersion,
          ejsVersion: current.ejsVersion,
          quickjsReady: current.quickjsReady,
          rustCrate: current.rustCrate,
          audioProcessor: current.audioProcessor,
          arch: current.arch,
          usingUpdatedYtDlp: current.usingUpdatedYtDlp,
          usingUpdatedEjs: current.usingUpdatedEjs,
          autoUpdateEnabled: saved,
          lastUpdateCheckMs: current.lastUpdateCheckMs,
        );
      }
      _statusMessage = saved
          ? 'Auto-actualización automática activada (cada 24 h al descargar).'
          : 'Auto-actualización automática desactivada.';
      notifyListeners();
    } catch (err) {
      _errorMessage = 'No se pudo guardar la preferencia: $err';
      notifyListeners();
    }
  }

  Future<void> checkForUpdates() async {
    if (isBusy) return;
    _isCheckingUpdates = true;
    _errorMessage = null;
    _statusMessage = 'Consultando versiones recientes en PyPI...';
    notifyListeners();

    try {
      final result = await _engine.checkYtEngineUpdates();
      _lastCheckResult = result;
      if (!result.ok) {
        _errorMessage = result.error.isNotEmpty
            ? result.error
            : 'No se pudo comprobar PyPI. Revisa tu conexión.';
        _statusMessage = null;
      } else if (result.hasUpdates) {
        final parts = <String>[];
        if (result.ytDlp.updateAvailable) {
          parts.add('yt-dlp ${result.ytDlp.latest}');
        }
        if (result.ytDlpEjs.updateAvailable) {
          parts.add('yt-dlp-ejs ${result.ytDlpEjs.latest}');
        }
        _statusMessage = 'Disponible: ${parts.join(' · ')}';
      } else {
        _statusMessage = 'yt-dlp y yt-dlp-ejs ya están en la última versión.';
      }
      await loadEngineDetails(includePython: true);
    } catch (err) {
      _errorMessage = 'Error al comprobar actualizaciones: $err';
      _statusMessage = null;
    } finally {
      _isCheckingUpdates = false;
      notifyListeners();
    }
  }

  Future<void> updateNow({bool force = false}) async {
    if (isBusy) return;
    _isUpdatingEngine = true;
    _errorMessage = null;
    _updateProgress = const YtUpdateProgressEvent(
      stage: 'checking',
      packageName: '',
      percent: 0,
      downloadedBytes: 0,
      totalBytes: 0,
      message: 'Comprobando paquetes en PyPI...',
    );
    _statusMessage = 'Actualizando yt-dlp y yt-dlp-ejs...';
    notifyListeners();

    try {
      final result = await _engine.updateYtEngine(force: force);
      if (!result.ok) {
        _errorMessage = result.error.isNotEmpty
            ? result.error
            : 'Error aplicando actualización desde PyPI.';
        _statusMessage = null;
      } else {
        _lastCheckResult = null;
        _statusMessage = result.message.isNotEmpty
            ? result.message
            : (result.updatedAny
                ? 'Motor actualizado correctamente desde PyPI.'
                : 'Todo el motor ya estaba actualizado.');
      }
      await loadEngineDetails(includePython: true);
    } catch (err) {
      _errorMessage = 'No se pudo completar la actualización: $err';
      _statusMessage = null;
    } finally {
      _isUpdatingEngine = false;
      _updateProgress = null;
      notifyListeners();
    }
  }

  Future<void> restoreBundled() async {
    if (isBusy) return;
    _isRestoringEngine = true;
    _errorMessage = null;
    _statusMessage = 'Restaurando versiones incluidas en el APK...';
    notifyListeners();

    try {
      await _engine.restoreBundledYtEngine();
      _lastCheckResult = null;
      await loadEngineDetails(includePython: true);
      _statusMessage =
          'Se restauraron yt-dlp y yt-dlp-ejs integrados en el APK.';
    } catch (err) {
      _errorMessage = 'No se pudo restaurar la versión del APK: $err';
      _statusMessage = null;
    } finally {
      _isRestoringEngine = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }
}
