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
import 'package:provider/provider.dart';
import 'core/audio/exoplayer_bridge.dart';
import 'core/storage/library_database.dart';
import 'core/theme/aura_theme.dart';
import 'screens/app_shell.dart';
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
        home: const AppShell(),
      ),
    );
  }
}
