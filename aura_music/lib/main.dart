// =============================================================================
// main.dart — Punto de entrada de Aura Music
// -----------------------------------------------------------------------------
// Qué hace este archivo:
//   Arranca Aura Music de inmediato en modo claro ("Acoustic Warmth") sin
//   pantallas de carga bloqueantes. Registra los providers modulares y difiere
//   la hidratación de SQLite + conexión con ExoPlayer hasta después del primer
//   frame para lograr una experiencia instantánea al abrir la app.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/audio/exoplayer_bridge.dart';
import 'core/storage/library_database.dart';
import 'core/theme/aura_theme.dart';
import 'screens/app_shell.dart';
import 'screens/permissions/permissions_screen.dart';
import 'state/library_provider.dart';
import 'state/player_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AuraColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  final engine = ExoPlayerBridge();
  final database = LibraryDatabase();
  final libraryProvider = LibraryProvider(engine: engine, database: database);
  final playerProvider = PlayerProvider(engine: engine, library: libraryProvider);

  runApp(
    AuraMusicApp(
      libraryProvider: libraryProvider,
      playerProvider: playerProvider,
    ),
  );
}

class AuraMusicApp extends StatefulWidget {
  const AuraMusicApp({
    super.key,
    required this.libraryProvider,
    required this.playerProvider,
  });

  final LibraryProvider libraryProvider;
  final PlayerProvider playerProvider;

  @override
  State<AuraMusicApp> createState() => _AuraMusicAppState();
}

class _AuraMusicAppState extends State<AuraMusicApp> {
  @override
  void initState() {
    super.initState();
    // Diferir carga de SQLite y MediaController justo tras pintar el 1er frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await widget.libraryProvider.hydrate();
      await widget.playerProvider.initializeEngineDeferred();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<LibraryProvider>.value(
          value: widget.libraryProvider,
        ),
        ChangeNotifierProvider<PlayerProvider>.value(
          value: widget.playerProvider,
        ),
      ],
      child: MaterialApp(
        title: 'Aura Music',
        debugShowCheckedModeBanner: false,
        theme: AuraTheme.buildLightTheme(),
        home: const _PermissionsEntryGate(),
      ),
    );
  }
}

/// Compuerta inicial que verifica los permisos requeridos antes de mostrar
/// AppShell. Si falta algún permiso en tiempo de ejecución (o es el primer
/// arranque), muestra PermissionsScreen antes de entrar a la app.
class _PermissionsEntryGate extends StatefulWidget {
  const _PermissionsEntryGate();

  @override
  State<_PermissionsEntryGate> createState() => _PermissionsEntryGateState();
}

class _PermissionsEntryGateState extends State<_PermissionsEntryGate> {
  static const _prefGateSeen = 'permissions_gate_seen';
  static const _prefNotifSkipped = 'permissions_notif_skipped';

  bool _loading = true;
  bool _canEnterApp = false;

  @override
  void initState() {
    super.initState();
    _checkGateState();
  }

  Future<void> _checkGateState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final gateSeen = prefs.getBool(_prefGateSeen) ?? false;
      final skippedNotif = prefs.getBool(_prefNotifSkipped) ?? false;

      PermissionStatus notifStatus = PermissionStatus.granted;
      try {
        notifStatus = await Permission.notification.status;
      } catch (_) {
        notifStatus = PermissionStatus.granted;
      }

      final ready = gateSeen && (notifStatus.isGranted || skippedNotif);
      if (!mounted) return;
      setState(() {
        _canEnterApp = ready;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _canEnterApp = true;
        _loading = false;
      });
    }
  }

  Future<void> _completeGate({required bool skippedNotifications}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefGateSeen, true);
      await prefs.setBool(_prefNotifSkipped, skippedNotifications);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _canEnterApp = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AuraColors.background,
        body: SizedBox.shrink(),
      );
    }

    if (_canEnterApp) {
      return const AppShell();
    }

    return PermissionsScreen(
      onEnterApp: () => _completeGate(skippedNotifications: false),
      onContinueWithoutNotifications: () =>
          _completeGate(skippedNotifications: true),
    );
  }
}
